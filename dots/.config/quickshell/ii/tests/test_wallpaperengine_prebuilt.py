# test_wallpaperengine_prebuilt.py — drives 4.wallpaperengine.sh's try_prebuilt
# in isolation against a local fixture "release" dir (WE_PREBUILT_DIR), with a
# fake quickshell binary so the smoke test can pass without real Qt.
import os, subprocess, tempfile, hashlib, json, shutil, pathlib
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
    (stage/"bin").mkdir(); (stage/"lib").mkdir()
    qs = stage/"bin"/"quickshell"
    qs.write_text(f"#!/bin/sh\nexit {fake_exits}\n"); qs.chmod(0o755)
    (stage/"lib"/"liblinux-wallpaperengine-lib.so").write_text("x")
    tb = dirpath/f"qs-wallpaperengine-{tag}-x86_64.tar.zst"
    # zstd via tar
    subprocess.run(["tar","--use-compress-program=zstd","-C",str(stage),
                    "-cf",str(tb),"bin","lib"], check=True)
    if tamper:
        with open(tb,"ab") as f: f.write(b"junk")
    (dirpath/"manifest.json").write_text(json.dumps(
        {"schema":1,"version":tag,"commit":"x","qt_min":qt_min,"arch":manifest_arch,
         "built_at":"t","files":["bin/quickshell","lib/liblinux-wallpaperengine-lib.so"]}))
    # SHA256SUMS computed over the ORIGINAL (pre-tamper is wrong on purpose when tamper=True)
    def sh(p):
        return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
    # deliberately hash the tarball as-it-should-be (re-pack clean copy for the sum)
    clean = dirpath/"_clean.tar.zst"
    subprocess.run(["tar","--use-compress-program=zstd","-C",str(stage),
                    "-cf",str(clean),"bin","lib"], check=True)
    sums = f"{sh(clean)}  {tb.name}\n{sh(dirpath/'manifest.json')}  manifest.json\n"
    (dirpath/"SHA256SUMS").write_text(sums)
    clean.unlink()
    shutil.rmtree(stage)

def run(env_extra):
    env = dict(os.environ)
    env.update({"INSTALL_WE":"1","WE_REF":"v0.0-test"})
    env.update(env_extra)
    # WE_INSTALL_PREFIX redirects the wrapper install away from /usr/local/bin
    return subprocess.run(["bash", str(SH)], env=env, capture_output=True, text=True)

def test_prebuilt_happy_path(tmp_path):
    rel = tmp_path/"rel"; rel.mkdir()
    make_release(rel)
    prefix = tmp_path/"prefix"; prefix.mkdir()
    cache = tmp_path/"cache"
    r = run({"WE_PREBUILT_DIR":str(rel), "WE_INSTALL_PREFIX":str(prefix),
             "BUILD_DIR":str(cache/"build"), "WE_SKIP_OPT_CHECK":"1"})
    assert r.returncode == 0, r.stderr
    assert (prefix/"bin"/"quickshell").exists(), "wrapper not installed"
    assert "prebuilt" in (r.stdout+r.stderr).lower()

def test_tamper_falls_back(tmp_path):
    rel = tmp_path/"rel"; rel.mkdir()
    make_release(rel, tamper=True)
    r = run({"WE_PREBUILT_DIR":str(rel), "WE_INSTALL_PREFIX":str(tmp_path/"p"),
             "BUILD_DIR":str(tmp_path/"b"), "WE_NO_SOURCE_FALLBACK":"1"})
    # fallback disabled for the test => nonzero, and it must NOT have installed
    assert r.returncode != 0
    assert "checksum" in (r.stdout+r.stderr).lower()

def test_arch_mismatch_falls_back(tmp_path):
    rel = tmp_path/"rel"; rel.mkdir()
    make_release(rel, manifest_arch="aarch64")   # x86_64-named tarball, aarch64 in manifest
    r = run({"WE_PREBUILT_DIR":str(rel), "WE_INSTALL_PREFIX":str(tmp_path/"p"),
             "BUILD_DIR":str(tmp_path/"b"), "WE_NO_SOURCE_FALLBACK":"1"})
    assert r.returncode != 0
    assert "arch" in (r.stdout+r.stderr).lower()

def test_smoke_failure_falls_back(tmp_path):
    rel = tmp_path/"rel"; rel.mkdir()
    make_release(rel, fake_exits=1)   # fake quickshell --version returns 1
    r = run({"WE_PREBUILT_DIR":str(rel), "WE_INSTALL_PREFIX":str(tmp_path/"p"),
             "BUILD_DIR":str(tmp_path/"b"), "WE_NO_SOURCE_FALLBACK":"1",
             "WE_SKIP_OPT_CHECK":"1"})
    assert r.returncode != 0
    assert "smoke" in (r.stdout+r.stderr).lower()
