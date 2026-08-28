#!/usr/bin/env python3
"""Drives the Phone tab's four shell scripts for real, with stubbed
`pgrep`, `pactl`, `v4l2-ctl`, `droidcam-cli`, `scrcpy` and `sudo` first on
PATH.

Nothing in this tree had ever RUN these scripts. `test_phone_sessions_
contract.py` reads them as source text - the state directory, the `pgrep -x`
rule - and `tst_phone_scrcpy.qml` drives the QML that parses their output
against strings a human typed, so a producer that stopped emitting those
strings stayed green on both sides. That is how a `stop video` that kills the
MICROPHONE, and a status probe whose JSON does not parse, both shipped.

What is stubbed and what is not: the stubs are the process TABLE (`pgrep`
answers with the pids this harness spawned) and the sound server (`pactl`
keeps a module list in a file). The processes themselves are real - launched
through `droidcam_session.sh launch`, with real pids and real
`/proc/<pid>/cmdline` - so the signature matching, the port disambiguation
and the kill guard all run against the thing they run against in production.
`droidcam-cli` cannot run on this machine at all (it is built against ffmpeg
8 and the system has 9), which is the other half of why the fakes are fakes.

The one artefact worth knowing: a fake `droidcam-cli` is a `#!` script, so
its cmdline carries the interpreter ahead of the path
(`bash /tmp/.../bin/droidcam-cli -nocontrols 10.0.0.5 4747`). Every rule
under test is a substring or a token test over that line, so the extra
leading words make the fixture harder rather than easier.
"""
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts" / "phone"
SESSION = SCRIPTS / "droidcam_session.sh"
STATUS = SCRIPTS / "droidcam_status.sh"
SETUP = SCRIPTS / "setup_droidcam_input.sh"
TEARDOWN = SCRIPTS / "teardown_droidcam_input.sh"
INSTALL = SCRIPTS / "install_droidcam.sh"

# `pgrep -x <name>` over the pids this harness spawned. Real pgrep would
# answer for the fake's INTERPRETER (a `#!` script's comm is `bash`), so the
# selection is the stub and everything the scripts then do with the pid -
# reading /proc, matching the signature, killing it - is real.
#
# It deliberately does NOT check that a pid is still alive. Real pgrep prints
# what the process table held when it sampled it, and the window between that
# sample and the reader's `open("/proc/<pid>/cmdline")` is one of the things
# under test - a stub that filtered dead pids would close it by hand.
FAKE_PGREP = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG/pgrep.argv"
if [ "${1:-}" != "-x" ]; then exit 2; fi
f="$FAKE_PROCS/${2:-}.pids"
[ -f "$f" ] || exit 1
missing=1
while read -r p; do
    [ -n "$p" ] || continue
    echo "$p"
    missing=0
done < "$f"
exit $missing
"""

# A stateful sound server: FAKE_PA/modules holds one "<index>\t<args>" row
# per loaded module. FAKE_PA_MONITOR_FORM picks how the server names a null
# sink's monitor source, and FAKE_PA_DESC whether it propagates the
# description - the two facts the setup script's lookups disagree about.
FAKE_PACTL = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG/pactl.argv"
M="$FAKE_PA/modules"; N="$FAKE_PA/next"
[ -f "$M" ] || : > "$M"
[ -f "$N" ] || echo 100 > "$N"
monitor_name() {
    case "${FAKE_PA_MONITOR_FORM:-plain}" in
        alsa_output) echo "alsa_output.DroidCam-Mic.monitor" ;;
        none)        echo "" ;;
        *)           echo "DroidCam-Mic.monitor" ;;
    esac
}
case "$*" in
    "list short sinks"|"list sinks short")
        while IFS=$'\t' read -r i a; do
            case "$a" in *sink_name=DroidCam-Mic*)
                printf '%s\tDroidCam-Mic\tPipeWire\ts16le 2ch 48000Hz\tSUSPENDED\n' "$i" ;;
            esac
        done < "$M" ;;
    "list short sources"|"list sources short")
        name="$(monitor_name)"
        printf '%s\n' "1	alsa_input.pci-0000_00_1f.3.analog-stereo	PipeWire	s32le 2ch 48000Hz	SUSPENDED"
        [ -n "$name" ] || exit 0
        while IFS=$'\t' read -r i a; do
            case "$a" in *sink_name=DroidCam-Mic*)
                printf '%s\t%s\tPipeWire\ts16le 2ch 48000Hz\tRUNNING\n' "$i" "$name" ;;
            esac
        done < "$M" ;;
    "list sources")
        name="$(monitor_name)"
        [ -n "$name" ] || exit 0
        while IFS=$'\t' read -r i a; do
            case "$a" in *sink_name=DroidCam-Mic*)
                printf 'Source #%s\n\tName: %s\n' "$i" "$name"
                if [ "${FAKE_PA_DESC:-1}" = "1" ]; then
                    printf '\tDescription: Monitor of DroidCam Microphone\n'
                else
                    printf '\tDescription: Monitor of DroidCam-Mic\n'
                fi ;;
            esac
        done < "$M" ;;
    "list short modules")
        while IFS=$'\t' read -r i a; do
            printf '%s\tmodule-null-sink\t%s\t\n' "$i" "$a"
        done < "$M" ;;
    load-module*)
        idx="$(cat "$N")"; echo $((idx + 1)) > "$N"
        shift
        printf '%s\t%s\n' "$idx" "$*" >> "$M"
        echo "$idx" ;;
    unload-module*)
        target="$2"; tmp="$M.tmp"; : > "$tmp"
        while IFS=$'\t' read -r i a; do
            [ "$i" = "$target" ] || printf '%s\t%s\n' "$i" "$a" >> "$tmp"
        done < "$M"
        mv "$tmp" "$M" ;;
esac
exit 0
"""

FAKE_V4L2_CTL = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG/v4l2-ctl.argv"
case "$*" in
    "--list-devices")
        printf 'DroidCam (platform:v4l2loopback-000):\n\t/dev/video10\n\n'
        exit 0 ;;
esac
exit 1
"""

# A fake camera/microphone/mirror that just stays alive. What matters is its
# cmdline, which the harness controls through the argv it is launched with -
# so it must NOT `exec` anything, or /proc would report the replacement's
# argv and every signature test would be measuring `sleep`. The short sleep
# is what makes the SIGTERM the scripts send land promptly: bash defers a
# trap until the command in front of it returns.
FAKE_SLEEPER = """#!/usr/bin/env bash
trap 'exit 0' TERM INT HUP
while :; do sleep 0.2; done
"""

FAKE_RECORDER = r"""#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "$FAKE_LOG/%(name)s.argv"
exit %(code)s
"""


def write_stub(path: Path, body: str) -> None:
    path.write_text(body)
    path.chmod(0o755)


class PhoneScriptHarness(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="imi-phone-scripts-"))
        self.addCleanup(self._cleanup)
        self.spawned = []
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.log = self.tmp / "log"
        self.log.mkdir()
        self.procs = self.tmp / "procs"
        self.procs.mkdir()
        self.pa = self.tmp / "pa"
        self.pa.mkdir()
        write_stub(self.bin / "pgrep", FAKE_PGREP)
        write_stub(self.bin / "pactl", FAKE_PACTL)
        write_stub(self.bin / "v4l2-ctl", FAKE_V4L2_CTL)
        write_stub(self.bin / "droidcam-cli", FAKE_SLEEPER)
        write_stub(self.bin / "scrcpy", FAKE_SLEEPER)
        self.env = dict(os.environ)
        self.env["PATH"] = f"{self.bin}:{self.env.get('PATH', '')}"
        self.env["FAKE_LOG"] = str(self.log)
        self.env["FAKE_PROCS"] = str(self.procs)
        self.env["FAKE_PA"] = str(self.pa)
        self.env["XDG_STATE_HOME"] = str(self.tmp / "state")
        self.env["HOME"] = str(self.tmp)
        self.state_dir = self.tmp / "state" / "quickshell" / "imi" / "phone"

    def _cleanup(self):
        for pid in self.spawned:
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        shutil.rmtree(self.tmp, ignore_errors=True)

    # ---- helpers ---------------------------------------------------------

    def run_script(self, script, *args, stdin=subprocess.DEVNULL, env_extra=None):
        env = dict(self.env)
        env.update(env_extra or {})
        return subprocess.run(["bash", str(script), *args], capture_output=True,
                              text=True, env=env, stdin=stdin, timeout=60)

    def launch(self, session, *argv, env_extra=None):
        """Start a real detached session through the script under test and
        register its pid with the fake process table."""
        res = self.run_script(SESSION, "launch", session, str(self.bin / argv[0]),
                              *argv[1:], env_extra=env_extra)
        self.assertEqual(res.returncode, 0, f"launch {session} failed: {res.stderr}")
        pid = int(res.stdout.strip())
        self.spawned.append(pid)
        binary = "scrcpy" if argv[0] == "scrcpy" else "droidcam-cli"
        with (self.procs / f"{binary}.pids").open("a") as handle:
            handle.write(f"{pid}\n")
        return pid

    def pgrep_calls(self):
        path = self.log / "pgrep.argv"
        return path.read_text().splitlines() if path.exists() else []

    def alive(self, pid):
        return Path(f"/proc/{pid}").exists()

    def dead_pid(self):
        """A pid nothing holds, for the between-pgrep-and-the-read window."""
        candidate = 4194300
        while Path(f"/proc/{candidate}").exists():
            candidate -= 1
        return candidate

    def modules(self):
        path = self.pa / "modules"
        return path.read_text().splitlines() if path.exists() else []


class DroidcamSessionTests(PhoneScriptHarness):
    def test_killall_stops_every_session_even_with_no_state_files(self):
        """`exit` inside a function ends the SCRIPT. cmd_stop's two non-kill
        paths ended with one, so the first session without a state file
        ended the loop and the other two were never stopped - and killall
        still exited 0, so the caller saw success."""
        res = self.run_script(SESSION, "killall")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.pgrep_calls(),
                         ["-x droidcam-cli", "-x droidcam-cli", "-x scrcpy"],
                         "killall did not reach all three sessions")

    def test_stopping_the_webcam_does_not_kill_the_microphone(self):
        """The shell restarts with only the mic running and video.json gone.
        `status video` used to answer with the MIC's pid - the video
        signature is a plain `droidcam-cli` substring and the audio process's
        cmdline contains it - so the tab drew a webcam stream that did not
        exist, and turning it off sent SIGTERM to the microphone."""
        mic = self.launch("audio", "droidcam-cli", "-a", "-nocontrols", "10.0.0.5", "4748")
        (self.state_dir / "video.json").unlink(missing_ok=True)

        status = json.loads(self.run_script(SESSION, "status", "video").stdout)
        self.assertFalse(status["alive"], f"status video adopted the microphone: {status}")
        self.assertEqual(status["pid"], "")
        self.assertFalse(status["video_running"])

        self.run_script(SESSION, "stop", "video")
        time.sleep(0.6)
        self.assertTrue(self.alive(mic), "stop video killed the microphone session")

    def test_the_microphone_is_still_found_by_its_own_name(self):
        """The mirror image: narrowing the video signature must not make the
        audio session unfindable."""
        mic = self.launch("audio", "droidcam-cli", "-a", "-nocontrols", "10.0.0.5", "4748")
        (self.state_dir / "audio.json").unlink()
        status = json.loads(self.run_script(SESSION, "status", "audio").stdout)
        self.assertTrue(status["alive"], f"the microphone was not rediscovered: {status}")
        self.assertEqual(status["pid"], str(mic))
        self.assertTrue(status["audio_running"])

    def test_a_scrcpy_mic_session_is_neither_the_webcam_nor_droidcam_audio(self):
        scrcpy = self.launch("scrcpy-mic", "scrcpy", "--no-video", "--no-window",
                             "--audio-source=mic", "--audio-buffer=50")
        for name in ("video.json", "scrcpy-mic.json"):
            (self.state_dir / name).unlink(missing_ok=True)
        video = json.loads(self.run_script(SESSION, "status", "video").stdout)
        self.assertFalse(video["alive"], f"status video adopted the scrcpy mic: {video}")
        mic = json.loads(self.run_script(SESSION, "status", "scrcpy-mic").stdout)
        self.assertEqual(mic["pid"], str(scrcpy))

    def test_a_rediscovered_session_reports_its_port_and_address(self):
        """`IFS` drops space, so the two rediscovery paths' unquoted `$cl`
        was one word: `extract_port` saw a single non-numeric argument and
        answered empty, and so did `extract_ip`."""
        self.launch("video", "droidcam-cli", "-nocontrols", "10.0.0.5", "4747")
        (self.state_dir / "video.json").unlink()
        status = json.loads(self.run_script(SESSION, "status", "video").stdout)
        self.assertTrue(status["alive"], status)
        self.assertEqual(status["port"], "4747")
        self.assertEqual(status["ip"], "10.0.0.5")
        self.assertEqual(status["mode"], "wifi")

    def test_a_rediscovered_usb_session_reports_usb_mode(self):
        self.launch("video", "droidcam-cli", "-nocontrols", "adb", "4747")
        (self.state_dir / "video.json").unlink()
        status = json.loads(self.run_script(SESSION, "status", "video").stdout)
        self.assertEqual(status["mode"], "usb")
        self.assertEqual(status["port"], "4747")

    def test_every_status_answer_is_json_the_shell_can_parse(self):
        for session in ("video", "audio", "scrcpy-mic"):
            res = self.run_script(SESSION, "status", session)
            json.loads(res.stdout)


class DroidcamStatusTests(PhoneScriptHarness):
    def _status(self, env_extra=None):
        res = self.run_script(STATUS, env_extra=env_extra)
        try:
            return json.loads(res.stdout), res
        except json.JSONDecodeError as error:
            self.fail(f"droidcam_status.sh emitted invalid JSON ({error}): {res.stdout!r}")

    def test_a_pid_that_exited_is_not_reported_as_a_running_webcam(self):
        """`/proc/<pid>/cmdline` was read with no readability guard, so a
        process that exited between the `pgrep` and the read produced an
        empty cmdline, fell through to the `*)` default - the video arm -
        and was reported as a live webcam on a dead pid."""
        (self.procs / "droidcam-cli.pids").write_text(f"{self.dead_pid()}\n")
        doc, res = self._status()
        self.assertFalse(doc["video_running"], doc)
        self.assertEqual(doc["video_pid"], 0)
        self.assertNotIn("No such file or directory", res.stderr)

    def test_the_payload_parses_when_the_port_is_not_four_digits(self):
        """`grep ... | tail -n1 || echo 0` never falls back: grep exits 1 and
        `tail` exits 0, so the pipeline succeeds with an empty answer and the
        unquoted `%s` emitted `"video_port":,`. That is invalid JSON, so
        QML's JSON.parse threw and EVERY field in the payload was lost."""
        pid = self.launch("video", "droidcam-cli", "-nocontrols", "10.0.0.5", "80")
        (self.procs / "droidcam-cli.pids").write_text(f"{pid}\n")
        doc, _ = self._status()
        self.assertTrue(doc["video_running"], doc)
        self.assertEqual(doc["video_port"], 80)

    def test_a_four_digit_port_still_reads(self):
        pid = self.launch("video", "droidcam-cli", "-nocontrols", "10.0.0.5", "4747")
        (self.procs / "droidcam-cli.pids").write_text(f"{pid}\n")
        doc, _ = self._status()
        self.assertEqual(doc["video_port"], 4747)
        self.assertEqual(doc["video_mode"], "wifi")

    def test_an_audio_session_is_not_counted_as_the_webcam(self):
        pid = self.launch("audio", "droidcam-cli", "-a", "-nocontrols", "10.0.0.5", "4748")
        (self.procs / "droidcam-cli.pids").write_text(f"{pid}\n")
        doc, _ = self._status()
        self.assertTrue(doc["audio_running"], doc)
        self.assertFalse(doc["video_running"], doc)

    def test_audio_source_is_the_source_name_this_file_documents(self):
        """The header documents a NAME (`alsa_output.droidcam_input.monitor`)
        and `tst_phone_scrcpy.qml` feeds `PhoneMic.parseStatus` a name; the
        awk printed pactl's INDEX."""
        self.run_script(SETUP)
        doc, _ = self._status()
        self.assertEqual(doc["audio_source"], "DroidCam-Mic.monitor")

    def test_the_payload_parses_with_nothing_running_at_all(self):
        doc, _ = self._status()
        self.assertFalse(doc["video_running"])
        self.assertEqual(doc["video_port"], 0)


class DroidcamInputTests(PhoneScriptHarness):
    def _setup_thrice(self, **env_extra):
        answers = []
        for _ in range(3):
            res = self.run_script(SETUP, env_extra=env_extra)
            answers.append((res.returncode, res.stdout.strip()))
        return answers

    def test_repeated_setup_loads_one_sink_however_the_server_names_the_monitor(self):
        """The existing-sink branch looked for `DroidCam-Mic.monitor` while
        the fresh-load branch below it tried `alsa_output.DroidCam-Mic.
        monitor` FIRST - two lookups for one fact. On a server using the
        `alsa_output.` form that does not also propagate the description,
        every call missed the sink it had already loaded and loaded another
        under the same name."""
        answers = self._setup_thrice(FAKE_PA_MONITOR_FORM="alsa_output", FAKE_PA_DESC="0")
        for code, name in answers:
            self.assertEqual(code, 0)
            self.assertEqual(name, "alsa_output.DroidCam-Mic.monitor")
        self.assertEqual(len(self.modules()), 1, "setup stacked null sinks")

    def test_repeated_setup_loads_one_sink_on_the_plain_naming(self):
        answers = self._setup_thrice(FAKE_PA_MONITOR_FORM="plain", FAKE_PA_DESC="1")
        for code, name in answers:
            self.assertEqual(code, 0)
            self.assertEqual(name, "DroidCam-Mic.monitor")
        self.assertEqual(len(self.modules()), 1)

    def test_a_setup_that_cannot_find_its_monitor_unloads_what_it_loaded(self):
        res = self.run_script(SETUP, env_extra={"FAKE_PA_MONITOR_FORM": "none"})
        self.assertEqual(res.returncode, 1, res.stdout)
        self.assertEqual(self.modules(), [],
                         "the failure path left the null sink resident")

    def test_teardown_unloads_every_copy_of_the_sink(self):
        """teardown's awk had an `exit` after the first match, so it removed
        exactly one module per call and duplicates accumulated."""
        for _ in range(3):
            self.run_script(SETUP, env_extra={"FAKE_PA_MONITOR_FORM": "none"})
        # Three loads that each failed to resolve a monitor; whatever is
        # resident, one teardown must clear all of it.
        (self.pa / "modules").write_text(
            "".join(f"{100 + i}\tmodule-null-sink sink_name=DroidCam-Mic\n" for i in range(3)))
        res = self.run_script(TEARDOWN)
        self.assertEqual(res.returncode, 0)
        self.assertEqual(self.modules(), [], "teardown left duplicate sinks behind")

    def test_teardown_leaves_other_modules_alone(self):
        (self.pa / "modules").write_text(
            "100\tmodule-null-sink sink_name=Other-Sink\n"
            "101\tmodule-null-sink sink_name=DroidCam-Mic\n")
        self.run_script(TEARDOWN)
        self.assertEqual(len(self.modules()), 1)
        self.assertIn("Other-Sink", self.modules()[0])


class InstallDroidcamTests(PhoneScriptHarness):
    """The installer is driven by sourcing it and calling `main <distro>`, so
    the branch under test does not depend on the machine running the suite:
    CI is Ubuntu and the maintainer is on Arch, and the Arch branch is the
    one with the defects."""

    def _install_bin(self, name, code=0, extra=""):
        write_stub(self.bin / name, FAKE_RECORDER % {"name": name, "code": code} + extra)

    def _main(self, distro, *, aur_code=0):
        self._install_bin("yay", aur_code)
        self._install_bin("sudo")
        self._install_bin("pacman")
        return subprocess.run(
            ["bash", "-c", 'source "$1"; main "$2"', "_", str(INSTALL), distro],
            capture_output=True, text=True, env=self.env,
            stdin=subprocess.DEVNULL, timeout=60)

    def test_a_failing_aur_helper_is_not_reported_as_a_successful_install(self):
        """The Arch branch printed "✓ DroidCam installed" after an unchecked
        `$AUR_HELPER -S`, and the footer then told the user the cards should
        read "Ready"."""
        res = self._main("arch", aur_code=1)
        self.assertNotEqual(res.returncode, 0, res.stdout)
        self.assertNotIn("✓ DroidCam installed", res.stdout)
        self.assertNotIn("now show 'Ready'", res.stdout)

    def test_the_arch_branch_installs_the_tools_the_webcam_needs(self):
        """`PhoneDeps` treats v4l-utils and android-tools as dependencies and
        `droidcam_status.sh` cannot report the webcam device without
        `v4l2-ctl`, so the Arch branch could complete with the webcam still
        unfindable."""
        res = self._main("arch")
        self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
        requested = " ".join(
            (self.log / name).read_text() if (self.log / name).exists() else ""
            for name in ("yay.argv", "sudo.argv", "pacman.argv"))
        self.assertIn("v4l-utils", requested)
        self.assertIn("android-tools", requested)
        self.assertIn("✓ DroidCam installed", res.stdout)

    def test_a_failed_extract_does_not_run_install_client_anywhere(self):
        """`unzip` and `cd` were both unchecked, so a failed extract left
        `sudo ./install-client` running in the CALLER's working directory."""
        self._install_bin("sudo")
        write_stub(self.bin / "curl",
                   '#!/usr/bin/env bash\nprev=""\nfor a in "$@"; do '
                   '[ "$prev" = "-o" ] && printf "not a zip" > "$a"; prev="$a"; done\nexit 0\n')
        write_stub(self.bin / "sha1sum",
                   '#!/usr/bin/env bash\necho "ce44abefbadec0a2183837605df23643ca13fb02  $1"\n')
        write_stub(self.bin / "unzip",
                   '#!/usr/bin/env bash\necho "cannot find zipfile directory" >&2\nexit 9\n')
        cwd = self.tmp / "cwd"
        cwd.mkdir()
        res = subprocess.run(
            ["bash", "-c", 'source "$1"; install_from_official_zip', "_", str(INSTALL)],
            capture_output=True, text=True, env=self.env, cwd=str(cwd),
            stdin=subprocess.DEVNULL, timeout=60)
        self.assertNotEqual(res.returncode, 0, res.stdout)
        self.assertNotIn("✓ DroidCam installed", res.stdout)
        sudo_log = self.log / "sudo.argv"
        ran = sudo_log.read_text() if sudo_log.exists() else ""
        self.assertNotIn("install-client", ran,
                         "install-client ran despite the extract failing")

    def test_sourcing_the_installer_installs_nothing(self):
        """The `main` split is only safe if sourcing the file is inert."""
        res = subprocess.run(
            ["bash", "-c", 'source "$1"; echo SOURCED', "_", str(INSTALL)],
            capture_output=True, text=True, env=self.env,
            stdin=subprocess.DEVNULL, timeout=30)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(res.stdout.strip(), "SOURCED")
        self.assertEqual(self.pgrep_calls(), [])

    def test_the_unsupported_branch_still_says_what_to_do_by_hand(self):
        res = self._main("unknown")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Unsupported distribution", res.stdout)


class ScriptHygieneTests(unittest.TestCase):
    def test_no_session_command_ends_a_function_with_exit(self):
        """The defect killall shipped with, as a rule: a command function
        returns, and the dispatch at the bottom is what sets the status."""
        text = SESSION.read_text()
        bodies = re.findall(r"^cmd_\w+\(\) \{\n(.*?)^\}", text, re.S | re.M)
        self.assertEqual(len(bodies), 4, "the four cmd_* functions were not found")
        for body in bodies:
            stripped = re.sub(r"^\s*#.*$", "", body, flags=re.M)
            self.assertNotRegex(stripped, r"(?<![\w-])exit \d",
                                "a cmd_* function exits the whole script")


if __name__ == "__main__":
    unittest.main()
