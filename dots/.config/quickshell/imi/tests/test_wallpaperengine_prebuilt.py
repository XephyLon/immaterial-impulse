#!/usr/bin/env python3
# test_wallpaperengine_prebuilt.py — drives 4.wallpaperengine.sh's try_prebuilt
# and its stamp/skip logic in isolation against a local fixture "release" dir
# (WE_PREBUILT_DIR), with a fake quickshell binary so the smoke test can pass
# without real Qt.
#
# unittest rather than pytest, and NOT bare `def test_*` functions: run_tests.sh
# invokes every Python check as `python3 <file>`, so a module of module-level
# test functions defines them, runs nothing and exits 0. This file shipped in
# that shape and was a silent no-op for its whole life (#91) - it never once
# executed, which is how a dead `up_to_date` skip path reached users.
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

# 4.wallpaperengine.sh lives at <repo>/sdata/subcmd-install/4.wallpaperengine.sh
ROOT = pathlib.Path(__file__).resolve()
while not (ROOT / "sdata").exists():
    ROOT = ROOT.parent
SH = ROOT / "sdata" / "subcmd-install" / "4.wallpaperengine.sh"


def make_release(dirpath, tag="v0.0-test", qt_min="6.0.0-1", manifest_arch="x86_64",
                 tamper=False, fake_exits=0):
    # The tarball is ALWAYS named x86_64 (releases are only cut for x86_64, and
    # the installer only ever requests that name). `manifest_arch` drives the
    # manifest's "arch" field so the manifest-arch gate can be exercised
    # independently of the filename.
    dirpath = pathlib.Path(dirpath)
    stage = pathlib.Path(tempfile.mkdtemp())
    (stage / "bin").mkdir()
    (stage / "lib").mkdir()
    qs = stage / "bin" / "quickshell"
    qs.write_text(f"#!/bin/sh\nexit {fake_exits}\n")
    qs.chmod(0o755)
    (stage / "lib" / "liblinux-wallpaperengine-lib.so").write_text("x")
    tb = dirpath / f"qs-wallpaperengine-{tag}-x86_64.tar.zst"
    subprocess.run(["tar", "--use-compress-program=zstd", "-C", str(stage),
                    "-cf", str(tb), "bin", "lib"], check=True)
    if tamper:
        with open(tb, "ab") as f:
            f.write(b"junk")
    (dirpath / "manifest.json").write_text(json.dumps(
        {"schema": 1, "version": tag, "commit": "x", "qt_min": qt_min, "arch": manifest_arch,
         "built_at": "t", "files": ["bin/quickshell", "lib/liblinux-wallpaperengine-lib.so"]}))

    def sh(p):
        return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

    # SHA256SUMS is computed over a CLEAN re-pack, so a tampered tarball is
    # exactly a checksum mismatch and nothing else.
    clean = dirpath / "_clean.tar.zst"
    subprocess.run(["tar", "--use-compress-program=zstd", "-C", str(stage),
                    "-cf", str(clean), "bin", "lib"], check=True)
    sums = f"{sh(clean)}  {tb.name}\n{sh(dirpath / 'manifest.json')}  manifest.json\n"
    (dirpath / "SHA256SUMS").write_text(sums)
    clean.unlink()
    shutil.rmtree(stage)


class WallpaperEnginePrebuiltTest(unittest.TestCase):
    # Every WE_* the script reads is pinned per-test, so a developer who happens
    # to have WE_FORCE_REBUILD or WE_STAMP_FILE exported cannot change what these
    # assert. PREBUILT_ROOT in particular used to default to the real
    # ~/.cache/immaterial-impulse, which meant running the suite wrote into the
    # user's actual install cache and let one test's extracted tree satisfy the
    # next test's -x check.
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.rel = self.tmp / "rel"
        self.rel.mkdir()
        self.prefix = self.tmp / "prefix"
        self.prefix.mkdir()
        self.stamp = self.tmp / "stamp"

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def env(self, **extra):
        env = dict(os.environ)
        for k in list(env):
            if k.startswith("WE_") or k in ("BUILD_DIR", "PREBUILT_ROOT"):
                del env[k]
        env.update({
            "INSTALL_WE": "1",
            "WE_REF": "v0.0-test",
            "WE_PREBUILT_DIR": str(self.rel),
            "WE_INSTALL_PREFIX": str(self.prefix),
            "BUILD_DIR": str(self.tmp / "b"),
            "PREBUILT_ROOT": str(self.tmp / "pb"),
            "WE_STAMP_FILE": str(self.stamp),
            "WE_SKIP_OPT_CHECK": "1",
            # No test may reach the real source build: it clones over the network
            # and compiles for tens of minutes. Tests that assert a fallback
            # keep this; the happy paths never get that far.
            "WE_NO_SOURCE_FALLBACK": "1",
        })
        env.update({k: str(v) for k, v in extra.items()})
        return env

    def run_installer(self, **extra):
        return subprocess.run(["bash", str(SH)], env=self.env(**extra),
                              capture_output=True, text=True, timeout=300)

    def fake_pacman(self, qt_version):
        # The host-Qt gate reads `pacman -Q qt6-base`. Off Arch there is no
        # pacman, host_qt comes back empty and the whole comparison
        # short-circuits - so without this stub that gate is unreachable and any
        # test claiming to cover it would be passing vacuously.
        bindir = self.tmp / "fakebin"
        bindir.mkdir(exist_ok=True)
        p = bindir / "pacman"
        p.write_text(f'#!/bin/sh\n[ "$1" = "-Q" ] && echo "qt6-base {qt_version}"\n')
        p.chmod(0o755)
        return str(bindir) + os.pathsep + os.environ.get("PATH", "")

    @staticmethod
    def out(r):
        return (r.stdout + r.stderr).lower()

    def test_prebuilt_happy_path(self):
        make_release(self.rel)
        r = self.run_installer()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.prefix / "bin" / "quickshell").exists(), "wrapper not installed")
        self.assertIn("prebuilt", self.out(r))

    def test_tamper_falls_back(self):
        make_release(self.rel, tamper=True)
        r = self.run_installer()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("checksum", self.out(r))
        self.assertFalse((self.prefix / "bin" / "quickshell").exists(),
                         "a tampered tarball must not install anything")

    def test_arch_mismatch_falls_back(self):
        # x86_64-named tarball, aarch64 in the manifest: the manifest gate has to
        # catch it on its own, without help from the filename.
        make_release(self.rel, manifest_arch="aarch64")
        r = self.run_installer()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("arch", self.out(r))
        self.assertFalse((self.prefix / "bin" / "quickshell").exists())

    def test_smoke_failure_falls_back(self):
        # fake quickshell --version returns 1
        make_release(self.rel, fake_exits=1)
        r = self.run_installer()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("smoke", self.out(r))
        self.assertFalse((self.prefix / "bin" / "quickshell").exists())

    def test_host_qt_older_than_build_qt_falls_back(self):
        # A prebuilt linked against a newer Qt than the host has will not load,
        # so the manifest's qt_min has to decline the binary before the smoke
        # test does. WE_SKIP_OPT_CHECK is left on so the only thing that can
        # reject this release is the version comparison.
        make_release(self.rel, qt_min="6.9.0-1")
        r = self.run_installer(PATH=self.fake_pacman("6.0.0-1"))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("qt", self.out(r))
        self.assertFalse((self.prefix / "bin" / "quickshell").exists())

    def test_host_qt_new_enough_installs(self):
        # The other side of the same gate: an equal-or-newer host Qt must NOT be
        # rejected. Without this, a version check that refused everything would
        # still satisfy the test above.
        make_release(self.rel, qt_min="6.0.0-1")
        r = self.run_installer(PATH=self.fake_pacman("6.9.0-1"))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.prefix / "bin" / "quickshell").exists())

    def test_second_run_skips_when_up_to_date(self):
        make_release(self.rel)
        r1 = self.run_installer()
        self.assertEqual(r1.returncode, 0, r1.stderr)
        self.assertTrue(self.stamp.exists(), "stamp not written after install")
        # Remove the release fixture entirely: the skip path must not need it,
        # because nothing is downloaded or built when the stamp matches. If the
        # skip does not fire, the run falls through to try_prebuilt (which now
        # has no fixture) and then to the source build, which is a hard failure
        # here rather than a silent slow path.
        shutil.rmtree(self.rel)
        r2 = self.run_installer()
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertIn("skipping", self.out(r2))

    def test_stamp_fields_are_individually_recoverable(self):
        # The regression this pins: write_stamp emits three fields and
        # up_to_date read them into two names, so bash's `read` folded the lib
        # dir into the binary path and `-x` could never pass. Asserting the file
        # merely "has three fields" would not have caught it - what matters is
        # that field 2 is a usable path on its own.
        make_release(self.rel)
        self.assertEqual(self.run_installer().returncode, 0)
        fields = self.stamp.read_text().split()
        self.assertEqual(len(fields), 3, f"expected 'ref bin lib', got {fields!r}")
        ref, binary, lib = fields
        self.assertEqual(ref, "v0.0-test")
        self.assertTrue(os.access(binary, os.X_OK),
                        f"stamp field 2 is not an executable on its own: {binary!r}")
        self.assertTrue(pathlib.Path(lib).is_dir(),
                        f"stamp field 3 is not a directory on its own: {lib!r}")

    def test_a_stamp_naming_a_missing_binary_does_not_skip(self):
        # up_to_date tests `-x` on the recorded binary because a matching ref
        # does not prove the build output survived: a cleared cache dir, a
        # pruned tmpfs or a manual rm all leave a current-looking stamp pointing
        # at nothing. Skip on that and the wrapper is rewritten to exec a file
        # that is not there, so the install reports success and the breakage
        # surfaces later, at shell start. Deleting the `-x` line passed every
        # other case in this file.
        make_release(self.rel)
        self.assertEqual(self.run_installer().returncode, 0)
        binary = pathlib.Path(self.stamp.read_text().split()[1])
        self.assertTrue(binary.exists(), "nothing recorded to delete")
        binary.unlink()
        # The fixture stays put, unlike the skip tests above: this run is
        # *supposed* to reinstall, so it needs something to reinstall from.
        r = self.run_installer()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("skipping", self.out(r),
                         "stamp ref matched but its binary was gone, and the install skipped anyway")
        self.assertTrue(binary.exists(), "the missing binary was not reinstalled")

    def test_skip_path_still_refreshes_the_wrapper(self):
        # The skip guards the expensive fetch/build, NOT the wrapper. A
        # wrapper-only fix has to reach an existing install, and once did not:
        # the stamp matched, the script exited early, and the old wrapper stayed
        # on disk, which is how an LD_LIBRARY_PATH leak survived an update and a
        # restart. Corrupt the wrapper, take the skip, and require it back.
        make_release(self.rel)
        self.assertEqual(self.run_installer().returncode, 0)
        wrapper = self.prefix / "bin" / "quickshell"
        wrapper.write_text("#!/bin/sh\n# stale wrapper from an older install\n")
        shutil.rmtree(self.rel)
        r = self.run_installer()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("skipping", self.out(r))
        body = wrapper.read_text()
        self.assertNotIn("stale wrapper", body, "skip path left the old wrapper in place")
        self.assertIn("QSG_RENDER_LOOP=threaded", body)

    def test_force_rebuild_overrides_skip(self):
        make_release(self.rel)
        self.assertEqual(self.run_installer().returncode, 0)
        r = self.run_installer(WE_FORCE_REBUILD="1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("prebuilt", self.out(r))
        self.assertNotIn("skipping", self.out(r))

    def test_stale_stamp_ref_does_not_skip(self):
        # Install first, then rewrite ONLY the ref. Everything else up_to_date
        # checks - the extracted binary, the installed wrapper - stays valid, so
        # the ref comparison is the only gate left that can decline the skip.
        #
        # Writing a stale stamp into a fresh prefix instead (the obvious shape,
        # and what this test used to do) proves nothing: with no wrapper
        # installed yet, up_to_date bails on the -x $PREFIX/bin/quickshell check
        # and never reaches the ref at all. That version passed with the ref
        # comparison deleted from the script entirely.
        make_release(self.rel)
        self.assertEqual(self.run_installer().returncode, 0)
        _ref, binary, lib = self.stamp.read_text().split()
        self.assertTrue(os.access(binary, os.X_OK))
        self.assertTrue((self.prefix / "bin" / "quickshell").exists())
        self.stamp.write_text(f"someOldRef {binary} {lib}\n")
        r = self.run_installer()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("skipping", self.out(r))
        self.assertEqual(self.stamp.read_text().split()[0], "v0.0-test", "stamp not refreshed")



@unittest.skipUnless(shutil.which("patchelf"), "patchelf not installed")
class RunpathRepairTests(unittest.TestCase):
    """ensure_standalone_libs must repair a binary that is currently running.

    patchelf rewrites in place, and the kernel refuses to write to a running
    executable (ETXTBSY). The shell *is* the binary being repaired, and
    Settings > Update Dots runs the installer from the shell - so in the only
    path a user actually takes, the target was always executing and the repair
    always failed. It failed silently (stderr to /dev/null) and the caller then
    advised installing patchelf, which was already installed.

    These drive the real functions, lifted out of the script, against a real
    ELF that is really executing.
    """

    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

        # A real ELF that needs a library only findable via RUNPATH: take a
        # stock binary and give it a NEEDED entry nothing can resolve yet.
        self.bin = self.tmp / "quickshell"
        shutil.copy2(shutil.which("sleep"), self.bin)
        self.lib_dir = self.tmp / "lib"
        self.lib_dir.mkdir()
        soname = "liblinux-wallpaperengine-lib.so"
        # Any real shared object satisfies ldd under this name.
        donor = subprocess.run(["bash", "-c", "ldd $(which sleep) | awk '/libc\\.so/{print $3}'"],
                               capture_output=True, text=True).stdout.strip()
        self.assertTrue(donor and os.path.exists(donor), "no donor .so found")
        shutil.copy2(donor, self.lib_dir / soname)
        subprocess.run(["patchelf", "--add-needed", soname, str(self.bin)], check=True)
        self.assertIn("not found", self._ldd(), "fixture does not start unresolved")

    def _ldd(self):
        env = dict(os.environ)
        env.pop("LD_LIBRARY_PATH", None)
        return subprocess.run(["ldd", str(self.bin)], capture_output=True,
                              text=True, env=env).stdout

    def _run_ensure(self):
        """Run the script's real ensure_standalone_libs against the fixture."""
        src = SH.read_text()
        start = src.index("libs_resolve_standalone(){")
        end = src.index("# Install the wrapper", start)
        harness = (
            'set -o pipefail\n'
            'OPT_LIBS="/opt/linux-wallpaperengine/lib:/opt/linux-wallpaperengine"\n'
            'say(){ printf "%s\\n" "$*"; }\n'
            + src[start:end] +
            f'\nensure_standalone_libs "{self.bin}" "{self.lib_dir}"\n'
        )
        return subprocess.run(["bash", "-c", harness], capture_output=True, text=True)

    def test_repairs_a_binary_that_is_not_running(self):
        proc = self._run_ensure()
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertNotIn("not found", self._ldd())

    def test_repairs_a_dependency_of_a_dependency(self):
        # DT_RUNPATH is NOT transitive. The executable's RUNPATH resolves its
        # own direct needs and nothing further: a bundled library's own needs
        # are searched using *that library's* RUNPATH. Repairing only the binary
        # therefore left the shell unable to start unaided, and the
        # LD_LIBRARY_PATH fallback - which IS transitive, which is precisely why
        # it worked where the RUNPATH did not - stayed in the wrapper.
        #
        # Build that shape: the bundled lib needs a second lib that only the
        # sibling directory can supply, and give it a RUNPATH that resolves
        # nothing, exactly as the shipped one does.
        inner = "libwe-inner-dep.so"
        shutil.copy2(self.lib_dir / "liblinux-wallpaperengine-lib.so",
                     self.lib_dir / inner)
        subprocess.run(["patchelf", "--add-needed", inner,
                        str(self.lib_dir / "liblinux-wallpaperengine-lib.so")], check=True)
        subprocess.run(["patchelf", "--set-rpath", "/nonexistent/builder/path",
                        str(self.lib_dir / "liblinux-wallpaperengine-lib.so")], check=True)
        self.assertIn("not found", self._ldd(), "fixture does not reproduce the shape")

        proc = self._run_ensure()
        self.assertEqual(proc.returncode, 0,
                         "transitive dependency left unresolved:\n" + proc.stdout + proc.stderr)
        self.assertNotIn("not found", self._ldd())

    def test_repairs_a_binary_that_IS_running(self):
        # The reported case. In-place patchelf returns ETXTBSY here; the repair
        # has to go through a copy and a rename.
        running = subprocess.Popen([str(self.bin), "30"],
                                   env={**os.environ, "LD_LIBRARY_PATH": str(self.lib_dir)})
        self.addCleanup(running.kill)
        proc = self._run_ensure()
        self.assertEqual(proc.returncode, 0,
                         "repair failed while the target was executing:\n"
                         + proc.stdout + proc.stderr)
        self.assertNotIn("not found", self._ldd())
        self.assertIn("baked the WE runtime lib dirs", proc.stdout)

    def test_the_running_process_survives_the_repair(self):
        # rename(2) swaps the directory entry; the live process keeps the inode
        # it already opened. Replacing the file in place would corrupt it.
        running = subprocess.Popen([str(self.bin), "30"],
                                   env={**os.environ, "LD_LIBRARY_PATH": str(self.lib_dir)})
        self.addCleanup(running.kill)
        self._run_ensure()
        self.assertIsNone(running.poll(), "the running process died during the repair")

    def test_failure_is_reported_not_swallowed(self):
        # Silence is what made this look like a missing dependency for months.
        os.chmod(self.tmp, 0o500)  # no new files beside the target -> mktemp fails
        self.addCleanup(os.chmod, self.tmp, 0o700)
        proc = self._run_ensure()
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("could not repair", proc.stdout)

if __name__ == "__main__":
    # A missing zstd is a hard failure, not a skip. These tests exist because
    # this file spent its life reporting success without running; "quietly
    # covered nothing" is the exact outcome being fixed, and a skip on a missing
    # tool is the same outcome wearing a different hat.
    if shutil.which("zstd") is None:
        raise SystemExit(
            "test_wallpaperengine_prebuilt.py: zstd not found, but the release "
            "fixtures are zstd tarballs. Install zstd and re-run; this check "
            "will not silently pass without exercising the installer."
        )
    unittest.main(verbosity=2)
