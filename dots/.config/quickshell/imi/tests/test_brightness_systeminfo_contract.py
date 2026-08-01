"""Contract checks for services/Brightness.qml and services/SystemInfo.qml.

Both services are Process/DBus wiring around small pockets of logic that QML
tests cannot reach without a display stack (Variants/Scope, Hyprland,
ddcutil), so the pockets are pinned here instead:

- Brightness: clamping, the never-fully-black floor, argv-array (non-shell)
  brightness commands, single-quote escaping of everything interpolated into
  the one bash -c pipeline, and the anti-flashbang response curve (its
  constants are extracted from the QML and evaluated numerically).
- SystemInfo: the /etc/os-release parse expressions (extracted and executed
  against a sample file), the distro→icon switch table (parsed with
  fall-through so additions are conscious), the refresh() restart pattern,
  and the absence of any interpolation into its shell commands.
"""

import math
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BRIGHTNESS = ROOT / "services" / "Brightness.qml"
SYSTEMINFO = ROOT / "services" / "SystemInfo.qml"


# ----------------------------------------------------------------- Brightness

def test_brightness_setters_clamp_to_unit_range():
    source = BRIGHTNESS.read_text()
    set_brightness = re.search(
        r"function setBrightness\(value: real\): void \{(.*?)\}", source, re.S
    )
    assert set_brightness, "setBrightness missing"
    assert "value = Math.max(0, Math.min(1, value));" in set_brightness.group(1)
    # The anti-flashbang multiplier product is clamped the same way.
    assert re.search(
        r"multipliedBrightness:\s*Math\.max\(0,\s*Math\.min\(1,\s*brightness \*", source
    )


def test_brightness_never_writes_fully_black():
    source = BRIGHTNESS.read_text()
    # DDC monitors: raw value floored at 1.
    assert "Math.max(Math.floor(brightnessValue * monitor.rawMaxBrightness), 1)" in source
    # Backlight: a computed 0% is rewritten to the minimum step.
    assert 'if (valuePercentNumber == 0) valuePercent = "1";' in source


def test_brightness_write_commands_are_argv_arrays_not_shell():
    source = BRIGHTNESS.read_text()
    assert 'setProc.exec(["ddcutil", "-b", busNum, "setvcp", "10", rawValueRounded])' in source
    assert re.search(r'setProc\.exec\(\["brightnessctl", "--class", "backlight", "s", valuePercent', source)


def test_brightness_shell_pipeline_escapes_every_interpolation():
    source = BRIGHTNESS.read_text()
    block = re.search(r'command: \["bash", "-c",\n(.*?)\n\s*\]', source, re.S)
    assert block, "anti-flashbang screenshot pipeline not found"
    interpolations = re.findall(r"\$\{([^}]*)\}", block.group(1))
    assert interpolations, "expected interpolations in the pipeline"
    for expr in interpolations:
        assert expr.startswith("StringUtils.shellSingleQuoteEscape("), (
            f"unescaped value spliced into bash -c: ${{{expr}}}"
        )


def test_antiflashbang_curve_constants_and_shape():
    source = BRIGHTNESS.read_text()
    match = re.search(
        r"return \(([\d.]+) \+ ([\d.]+) \* Math\.pow\(Math\.E, -([\d.]+) \* x\)\) / 100\.0;",
        source,
    )
    assert match, "brightnessMultiplierForLightness formula changed shape"
    offset, scale, decay = map(float, match.groups())
    assert (offset, scale, decay) == (6.600135, 216.360356, 0.0811129189)

    def f(x):
        return (offset + scale * math.e ** (-decay * x)) / 100.0

    # Dark content (lightness 0) boosts brightness, bright content dims it,
    # and the curve is monotone decreasing in between.
    assert f(0) > 2.0
    assert f(100) < 0.07
    samples = [f(x) for x in range(0, 101, 10)]
    assert all(a > b for a, b in zip(samples, samples[1:]))


def test_brightness_keys_gamma_before_backlight():
    source = BRIGHTNESS.read_text()
    # Increase: restore gamma to 100 first, only then raise panel brightness.
    assert "if (Hyprsunset.gamma !== 100)" in source
    assert "Hyprsunset.setGamma(Hyprsunset.gamma + 5);" in source
    # Decrease: drop gamma only once brightness has hit the floor.
    assert "Hyprsunset.setGamma(Hyprsunset.gamma - 5);" in source


# ----------------------------------------------------------------- SystemInfo

SAMPLE_OS_RELEASE = '''NAME="Arch Linux"
PRETTY_NAME="Arch Linux"
ID=arch
BUILD_ID=rolling
HOME_URL="https://archlinux.org/"
DOCUMENTATION_URL="https://wiki.archlinux.org/"
SUPPORT_URL="https://bbs.archlinux.org/"
BUG_REPORT_URL="https://gitlab.archlinux.org/groups/archlinux/-/issues"
PRIVACY_POLICY_URL="https://terms.archlinux.org/docs/privacy-policy/"
LOGO=archlinux-logo
'''


def _extract_js_regex(source: str, var_name: str) -> str:
    match = re.search(rf"const {var_name} = textOsRelease\.match\(/(.*?)/m\)", source)
    assert match, f"{var_name} regex not found"
    return match.group(1)


def test_os_release_parse_expressions_extract_expected_fields():
    source = SYSTEMINFO.read_text()
    # The JS regex literals are extracted from the QML and executed here with
    # the same MULTILINE semantics, against a representative os-release.
    cases = {
        "prettyNameMatch": "Arch Linux",
        "idMatch": "arch",
        "homeUrlMatch": "https://archlinux.org/",
        "documentationUrlMatch": "https://wiki.archlinux.org/",
        "supportUrlMatch": "https://bbs.archlinux.org/",
        "bugReportUrlMatch": "https://gitlab.archlinux.org/groups/archlinux/-/issues",
        "privacyPolicyUrlMatch": "https://terms.archlinux.org/docs/privacy-policy/",
        "logoFieldMatch": "archlinux-logo",
    }
    for var, expected in cases.items():
        pattern = _extract_js_regex(source, var)
        got = re.search(pattern, SAMPLE_OS_RELEASE, re.M)
        assert got and got.group(1) == expected, f"{var}: {pattern!r} -> {got}"

    # Quoted ID= values are unwrapped too.
    id_pattern = _extract_js_regex(source, "idMatch")
    got = re.search(id_pattern, 'ID="ubuntu"\n', re.M)
    assert got and got.group(1) == "ubuntu"

    # NAME fallback strips the word Linux when PRETTY_NAME is missing.
    assert 'nameMatch[1].replace(/Linux/i, "").trim()' in source


def _parse_icon_switch(source: str) -> dict:
    block = re.search(r"switch \(distroId\) \{(.*?)\n            \}", source, re.S)
    assert block, "distro icon switch not found"
    mapping = {}
    pending = []
    for label, default, icon in re.findall(
        r'case "([\w-]+)":|(default):|distroIcon = "([\w-]+)"', block.group(1)
    ):
        if label:
            pending.append(label)
        elif default:
            pending.append("default")
        elif icon:
            for key in pending:
                mapping[key] = icon
            pending = []
    return mapping


def test_distro_icon_table_is_pinned():
    source = SYSTEMINFO.read_text()
    assert _parse_icon_switch(source) == {
        "artix": "arch-symbolic",
        "arch": "arch-symbolic",
        "endeavouros": "endeavouros-symbolic",
        "cachyos": "cachyos-symbolic",
        "nixos": "nixos-symbolic",
        "fedora": "fedora-symbolic",
        "linuxmint": "ubuntu-symbolic",
        "ubuntu": "ubuntu-symbolic",
        "zorin": "ubuntu-symbolic",
        "popos": "ubuntu-symbolic",
        "debian": "debian-symbolic",
        "raspbian": "debian-symbolic",
        "kali": "debian-symbolic",
        "funtoo": "gentoo-symbolic",
        "gentoo": "gentoo-symbolic",
        "default": "arch-symbolic",
    }, "distro→icon mapping changed; update consciously"
    # Nyarch easter egg and the LOGO fallback stay in place.
    assert 'distroIcon = "nyarch-symbolic"' in source
    assert re.search(r"if \(logo\.trim\(\)\.length === 0\)\s*\n\s*logo = distroIcon", source)


def test_refresh_restarts_every_collector_process():
    source = SYSTEMINFO.read_text()
    body = re.search(r"function refresh\(\) \{(.*?)\}", source, re.S)
    assert body, "refresh() missing"
    for proc in ("getCpu", "getGpu", "getMemory", "getDisk",
                 "getShell", "getPackages", "getInstallAge", "getKernel"):
        # Stop-then-start: assigning running=true on an already-running
        # Process is a no-op, so the false write is what makes refresh real.
        assert f"{proc}.running = false" in body.group(1), proc
        assert f"{proc}.running = true" in body.group(1), proc
    hostname = re.search(r"function refreshHostname\(\) \{(.*?)\}", source, re.S)
    assert hostname
    assert "getHostname.running = false" in hostname.group(1)
    assert "getHostname.running = true" in hostname.group(1)


def test_systeminfo_shell_commands_contain_no_interpolation():
    # Repo hard rule: no external data spliced into bash -c. SystemInfo's
    # commands are all static strings — keep them that way.
    assert "${" not in SYSTEMINFO.read_text()


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
