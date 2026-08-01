# Prebuilt qs-wallpaperengine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a prebuilt patched-Quickshell + linux-wallpaperengine tarball via GitHub Releases so the installer downloads+verifies a binary (seconds) instead of compiling from source (~5-40 min), with an automatic source-build fallback.

**Architecture:** Two repos. In `XephyLon/qs-wallpaperengine`: a shared `scripts/build-we.sh` (single source of build truth) + `scripts/package-we.sh` (tarball/manifest/checksums) + a `release.yml` GH Actions workflow that builds on `v*` tags and publishes a Release. In `imi-unify`: `sdata/subcmd-install/4.wallpaperengine.sh` gains a `try_prebuilt` fast-path (download → sha256 verify → Qt gate → extract → smoke-test → install wrapper) that falls back to `build-we.sh` on any miss. No system ends up worse than today.

**Tech Stack:** bash, GitHub Actions (Arch container), cmake/ninja, `tar --zstd`, `sha256sum`, `curl`, `gh`.

> **Status: implemented 2026-07-24** (local commits, not pushed). Two reconciliations vs. the verbatim code below, made during execution:
> - `build-we.sh` routes all bootstrap/cmake/ninja output to **stderr** so stdout carries only the `QS_BIN=`/`WE_LIB_DIR=` lines the `eval "$(…)"` consumers capture (otherwise build noise would be eval'd).
> - `WE_INSTALL_PREFIX` is a **prefix root** (`/usr/local`), binaries land in `$PREFIX/bin` — resolves an inconsistency between this plan's script snippet (bindir) and its test (prefix root). Production path is unchanged: `/usr/local/bin/quickshell` + `qs`.
> Not yet done: cut an actual `vX.Y.Z` tag/release and bump `WE_REF` off the commit pin (manual, when ready — see `qs-wallpaperengine/docs/cutting-a-release.md`).

---

## Repo layout / responsibilities

- `qs-wallpaperengine/scripts/build-we.sh` — clone-agnostic build: assumes it runs inside a qs-wallpaperengine checkout, runs `bootstrap.sh`, builds the WE lib and the patched Quickshell (`build2`), prints the resulting `QS_BIN` and `WE_LIB_DIR`. Used by BOTH CI and the installer's fallback.
- `qs-wallpaperengine/scripts/package-we.sh` — given `QS_BIN`, `WE_LIB_DIR`, and a tag, assemble `bin/`+`lib/`+`manifest.json` into `qs-wallpaperengine-<tag>-x86_64.tar.zst` and a `SHA256SUMS`.
- `qs-wallpaperengine/.github/workflows/release.yml` — on `v*` tag / manual dispatch: install deps → `build-we.sh` → `package-we.sh` → smoke-test → `gh release`.
- `imi-unify/sdata/subcmd-install/4.wallpaperengine.sh` — `try_prebuilt` fast-path + `install_wrapper` helper + source fallback that clones the repo (as today) then delegates the compile to `build-we.sh`.

The system `linux-wallpaperengine-git` package (`/opt/linux-wallpaperengine`) stays a runtime prerequisite exactly as today — neither the tarball nor this plan changes that.

---

## Constraints for the implementer (this repo's standing rules)

- Do NOT push or create releases/tags unless the controller says so. Commit locally only.
- In `~/dev/qs-wallpaperengine` (the user's dirty WIP), commit ONLY the files this plan creates/edits; leave every other dirty file (README.md, test/vid.qml, CHANGELOG.md, VERSION) untouched. `git add` explicit paths, never `git add -A`.
- Never splice remote/external values into a `bash -c` string. Validate tag/arch/version against a whitelist regex and pass as argv. Verify downloads with `sha256sum -c` BEFORE executing or installing anything.
- Preserve granular commit history — one commit per task/logical step; no squashing.
- No Claude/agent attribution in commit messages.

---

## Task 1: `build-we.sh` — extract the build into a shared script (qs-wallpaperengine repo)

**Files:**
- Create: `~/dev/qs-wallpaperengine/scripts/build-we.sh`
- Test: `~/dev/qs-wallpaperengine/scripts/test_build_we.sh`

The compile commands are copied verbatim from `imi-unify/sdata/subcmd-install/4.wallpaperengine.sh` (steps 2-4). This script does NOT clone qs-wallpaperengine (the caller already has the checkout) — it only bootstraps the two upstreams and compiles.

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# test_build_we.sh — static checks only (a real compile is exercised by CI).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
s="$here/build-we.sh"
[[ -f "$s" ]]            || { echo "FAIL: build-we.sh missing"; exit 1; }
bash -n "$s"            || { echo "FAIL: syntax"; exit 1; }
grep -q 'build2' "$s"   || { echo "FAIL: must configure the build2 dir"; exit 1; }
grep -q 'WALLPAPERENGINE_SRC' "$s" || { echo "FAIL: must pass WALLPAPERENGINE_SRC"; exit 1; }
# Must be dispatchable with --print-paths without building.
out="$(REPO_ROOT=/nonexistent bash "$s" --print-paths 2>/dev/null)" || true
grep -q 'QS_BIN=' <<<"$out" || { echo "FAIL: --print-paths must emit QS_BIN="; exit 1; }
echo "PASS"
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bash ~/dev/qs-wallpaperengine/scripts/test_build_we.sh`
Expected: `FAIL: build-we.sh missing`

- [ ] **Step 3: Write `build-we.sh`**

```bash
#!/usr/bin/env bash
# build-we.sh — build the patched Quickshell (Quickshell.WallpaperEngine module)
# + linux-wallpaperengine from a qs-wallpaperengine checkout. Single source of
# build truth: called by CI (.github/workflows/release.yml) and by the
# installer's source-build fallback (imi-unify 4.wallpaperengine.sh). Does NOT
# clone this repo — the caller provides the checkout at $REPO_ROOT.
#
# Usage:
#   bash build-we.sh              # bootstrap + compile; prints QS_BIN=/WE_LIB_DIR=
#   bash build-we.sh --print-paths  # print the paths without building
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
JOBS="${WE_BUILD_JOBS:-$(nproc)}"

WE_SRC="$REPO_ROOT/build/linux-wallpaperengine"
QS_SRC="$REPO_ROOT/build/quickshell"
QS_BIN="$QS_SRC/build2/src/quickshell"
WE_LIB_DIR="$WE_SRC/build/output"

print_paths(){ printf 'QS_BIN=%s\nWE_LIB_DIR=%s\n' "$QS_BIN" "$WE_LIB_DIR"; }

if [[ "${1:-}" == "--print-paths" ]]; then print_paths; exit 0; fi

# --- 1. Clone+patch both upstreams (bootstrap.sh is idempotent) -------------
cd "$REPO_ROOT"
bash ./bootstrap.sh

export WALLPAPERENGINE_SRC="$WE_SRC/src"

# --- 2. Build linux-wallpaperengine (the FBO-driver lib) --------------------
cmake -S "$WE_SRC" -B "$WE_SRC/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$WE_SRC/build" -j"$JOBS"

# --- 3. Build the patched Quickshell into build2 (Ninja; see 4.wallpaper...) -
rm -rf "$QS_SRC/build2"
cmake -GNinja -S "$QS_SRC" -B "$QS_SRC/build2" -DCMAKE_BUILD_TYPE=Release \
  -DWALLPAPERENGINE_SRC="$WE_SRC/src" -DWALLPAPERENGINE_BUILD="$WE_SRC/build" \
  -DSERVICE_MPRIS=ON -DSERVICE_NOTIFICATIONS=ON -DSERVICE_PAM=ON \
  -DSERVICE_PIPEWIRE=ON -DSERVICE_POLKIT=ON -DSERVICE_STATUS_NOTIFIER=ON \
  -DSERVICE_UPOWER=ON -DBLUETOOTH=ON
cmake --build "$QS_SRC/build2" -j"$JOBS"

[[ -x "$QS_BIN" ]] || { echo "build-we.sh: $QS_BIN missing after build" >&2; exit 1; }
print_paths
```

- [ ] **Step 4: Run the test, verify PASS**

Run: `bash ~/dev/qs-wallpaperengine/scripts/test_build_we.sh`
Expected: `PASS`

- [ ] **Step 5: Commit** (in qs-wallpaperengine, explicit paths only)

```bash
cd ~/dev/qs-wallpaperengine
git add scripts/build-we.sh scripts/test_build_we.sh
git commit -m "build: shared build-we.sh (single source of WE build truth)"
```

---

## Task 2: `package-we.sh` — assemble tarball + manifest + checksums (qs-wallpaperengine repo)

**Files:**
- Create: `~/dev/qs-wallpaperengine/scripts/package-we.sh`
- Test: `~/dev/qs-wallpaperengine/scripts/test_package_we.sh`

- [ ] **Step 1: Write the failing test** (uses fixtures, no real binary needed)

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
s="$here/package-we.sh"
[[ -f "$s" ]] || { echo "FAIL: package-we.sh missing"; exit 1; }
bash -n "$s"  || { echo "FAIL: syntax"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/qsbin" "$tmp/welib" "$tmp/out"
printf '#!/bin/sh\necho quickshell 0.0-test\n' > "$tmp/qsbin/quickshell"; chmod +x "$tmp/qsbin/quickshell"
printf 'x' > "$tmp/welib/liblinux-wallpaperengine-lib.so"
printf 'y' > "$tmp/welib/libcef.so"

WE_QT_VERSION=6.11.1-1 WE_COMMIT=deadbeef \
  bash "$s" --qs-bin "$tmp/qsbin/quickshell" --lib-dir "$tmp/welib" \
            --tag v0.0-test --out "$tmp/out"

tb="$tmp/out/qs-wallpaperengine-v0.0-test-x86_64.tar.zst"
[[ -f "$tb" ]]                       || { echo "FAIL: tarball not produced"; exit 1; }
[[ -f "$tmp/out/manifest.json" ]]    || { echo "FAIL: manifest missing"; exit 1; }
[[ -f "$tmp/out/SHA256SUMS" ]]       || { echo "FAIL: SHA256SUMS missing"; exit 1; }
grep -q '"qt_min": *"6.11.1-1"' "$tmp/out/manifest.json" || { echo "FAIL: qt_min not recorded"; exit 1; }
grep -q '"arch": *"x86_64"' "$tmp/out/manifest.json"     || { echo "FAIL: arch not recorded"; exit 1; }
( cd "$tmp/out" && sha256sum -c SHA256SUMS >/dev/null )  || { echo "FAIL: checksums don't verify"; exit 1; }
# tarball must contain bin/quickshell and lib/*.so
tar --use-compress-program=unzstd -tf "$tb" | grep -q '^bin/quickshell$' || { echo "FAIL: no bin/quickshell in tar"; exit 1; }
tar --use-compress-program=unzstd -tf "$tb" | grep -q '^lib/libcef.so$'  || { echo "FAIL: libs not bundled"; exit 1; }
echo "PASS"
```

- [ ] **Step 2: Run it, verify it fails** — Expected: `FAIL: package-we.sh missing`

- [ ] **Step 3: Write `package-we.sh`**

```bash
#!/usr/bin/env bash
# package-we.sh — assemble a prebuilt qs-wallpaperengine release artifact:
#   <out>/qs-wallpaperengine-<tag>-x86_64.tar.zst   (bin/quickshell + lib/*.so*)
#   <out>/manifest.json                             (version, commit, qt_min, arch, files)
#   <out>/SHA256SUMS                                (over the tarball + manifest)
set -euo pipefail

QS_BIN="" LIB_DIR="" TAG="" OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --qs-bin)  QS_BIN="$2"; shift 2;;
    --lib-dir) LIB_DIR="$2"; shift 2;;
    --tag)     TAG="$2"; shift 2;;
    --out)     OUT="$2"; shift 2;;
    *) echo "package-we.sh: unknown arg $1" >&2; exit 2;;
  esac
done
[[ -x "$QS_BIN" && -d "$LIB_DIR" && -n "$TAG" && -n "$OUT" ]] || {
  echo "usage: package-we.sh --qs-bin B --lib-dir D --tag T --out O" >&2; exit 2; }
[[ "$TAG" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "package-we.sh: bad tag $TAG" >&2; exit 2; }

ARCH="$(uname -m)"
QT_MIN="${WE_QT_VERSION:-$(pacman -Q qt6-base 2>/dev/null | awk '{print $2}')}"
COMMIT="${WE_COMMIT:-unknown}"
BUILT_AT="${WE_BUILT_AT:-unknown}"   # CI passes an ISO timestamp; scripts can't call date() deterministically in tests

mkdir -p "$OUT"
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/bin" "$stage/lib"
install -m755 "$QS_BIN" "$stage/bin/quickshell"
# copy every regular .so* the WE build produced (libcef, libEGL, libGLESv2,
# libvk_swiftshader, liblinux-wallpaperengine-lib.so, ...)
find "$LIB_DIR" -maxdepth 1 -type f -name '*.so*' -exec cp -a {} "$stage/lib/" \;

# manifest.json (hand-built JSON; values are our own, no external interpolation)
files_json="$(cd "$stage" && find bin lib -type f | sort | sed 's/.*/"&"/' | paste -sd, -)"
cat > "$OUT/manifest.json" <<JSON
{
  "schema": 1,
  "version": "$TAG",
  "commit": "$COMMIT",
  "qt_min": "$QT_MIN",
  "arch": "$ARCH",
  "built_at": "$BUILT_AT",
  "files": [$files_json]
}
JSON

tarball="qs-wallpaperengine-${TAG}-${ARCH}.tar.zst"
tar --use-compress-program='zstd -19 -T0' -C "$stage" -cf "$OUT/$tarball" bin lib

( cd "$OUT" && sha256sum "$tarball" manifest.json > SHA256SUMS )
echo "package-we.sh: wrote $OUT/$tarball + manifest.json + SHA256SUMS"
```

- [ ] **Step 4: Run the test, verify PASS** — `bash ~/dev/qs-wallpaperengine/scripts/test_package_we.sh`

- [ ] **Step 5: Commit**

```bash
cd ~/dev/qs-wallpaperengine
git add scripts/package-we.sh scripts/test_package_we.sh
git commit -m "build: package-we.sh (tarball + manifest + SHA256SUMS)"
```

---

## Task 3: `release.yml` — CI that builds + publishes on tag (qs-wallpaperengine repo)

**Files:**
- Create: `~/dev/qs-wallpaperengine/.github/workflows/release.yml`
- Test: `~/dev/qs-wallpaperengine/.github/workflows/test_release_yaml.sh`

Deps strategy (low drift): install `yay`, fully install `linux-wallpaperengine-git` (provides `/opt/linux-wallpaperengine` runtime + its own makedepends), and install Quickshell's makedepends by extracting them from the `quickshell-git` PKGBUILD via `yay -G` (NO package build). Then run `build-we.sh`.

- [ ] **Step 1: Write the failing test** (structural YAML lint; `act` isn't available)

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
y="$here/release.yml"
[[ -f "$y" ]] || { echo "FAIL: release.yml missing"; exit 1; }
python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$y" || { echo "FAIL: invalid YAML"; exit 1; }
grep -q "tags:" "$y"              || { echo "FAIL: no tag trigger"; exit 1; }
grep -q "workflow_dispatch" "$y"  || { echo "FAIL: no manual dispatch"; exit 1; }
grep -q "build-we.sh" "$y"        || { echo "FAIL: does not call build-we.sh"; exit 1; }
grep -q "package-we.sh" "$y"      || { echo "FAIL: does not call package-we.sh"; exit 1; }
grep -q "gh release create" "$y"  || { echo "FAIL: does not publish a release"; exit 1; }
echo "PASS"
```

- [ ] **Step 2: Run it, verify it fails** — Expected: `FAIL: release.yml missing`

- [ ] **Step 3: Write `release.yml`**

```yaml
name: release
on:
  push:
    tags: ["v*"]
  workflow_dispatch:
    inputs:
      tag:
        description: "Tag to build/publish (e.g. v0.1.0)"
        required: true

permissions:
  contents: write   # gh release create

jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: archlinux:latest
    steps:
      - name: Resolve tag
        id: t
        run: echo "tag=${GITHUB_REF_NAME:-${{ github.event.inputs.tag }}}" >> "$GITHUB_OUTPUT"

      - name: Base tooling
        run: |
          pacman -Syu --noconfirm --needed base-devel git sudo cmake ninja zstd python \
            qt6-base qt6-declarative qt6-wayland github-cli
          # unprivileged build user (makepkg/yay refuse to run as root)
          useradd -m build && echo "build ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

      - name: yay
        run: |
          sudo -u build bash -c 'cd /tmp && git clone https://aur.archlinux.org/yay-bin.git \
            && cd yay-bin && makepkg -si --noconfirm'

      - name: Runtime + build deps
        run: |
          # /opt/linux-wallpaperengine (runtime) + its makedepends, full build:
          sudo -u build yay -S --noconfirm --needed linux-wallpaperengine-git
          # Quickshell makedepends only (no package build): extract from PKGBUILD
          sudo -u build bash -c 'cd /tmp && yay -G quickshell-git && cd quickshell-git \
            && source PKGBUILD && sudo pacman -S --noconfirm --needed --asdeps \
               "${makedepends[@]}" "${depends[@]}"'

      - uses: actions/checkout@v4

      - name: Build
        id: build
        run: |
          chown -R build:build "$GITHUB_WORKSPACE"
          eval "$(sudo -u build env REPO_ROOT="$GITHUB_WORKSPACE" bash scripts/build-we.sh)"
          echo "qs_bin=$QS_BIN"       >> "$GITHUB_OUTPUT"
          echo "we_lib_dir=$WE_LIB_DIR" >> "$GITHUB_OUTPUT"

      - name: Package
        run: |
          mkdir -p out
          WE_QT_VERSION="$(pacman -Q qt6-base | awk '{print $2}')" \
          WE_COMMIT="${GITHUB_SHA}" WE_BUILT_AT="build-${{ steps.t.outputs.tag }}" \
          bash scripts/package-we.sh \
            --qs-bin "${{ steps.build.outputs.qs_bin }}" \
            --lib-dir "${{ steps.build.outputs.we_lib_dir }}" \
            --tag "${{ steps.t.outputs.tag }}" --out out

      - name: Smoke test the packaged binary
        run: |
          d="$(mktemp -d)"
          tar --use-compress-program=unzstd \
            -xf out/qs-wallpaperengine-${{ steps.t.outputs.tag }}-x86_64.tar.zst -C "$d"
          LD_LIBRARY_PATH="$d/lib:/opt/linux-wallpaperengine/lib:/opt/linux-wallpaperengine" \
            "$d/bin/quickshell" --version

      - name: Publish release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "${{ steps.t.outputs.tag }}" \
            out/qs-wallpaperengine-${{ steps.t.outputs.tag }}-x86_64.tar.zst \
            out/manifest.json out/SHA256SUMS \
            --title "${{ steps.t.outputs.tag }}" \
            --notes "Prebuilt WE-capable Quickshell (x86_64). Installer verifies SHA256SUMS and falls back to a source build on any mismatch."
```

- [ ] **Step 4: Run the test, verify PASS** — `bash ~/dev/qs-wallpaperengine/.github/workflows/test_release_yaml.sh`

- [ ] **Step 5: Commit**

```bash
cd ~/dev/qs-wallpaperengine
git add .github/workflows/release.yml .github/workflows/test_release_yaml.sh
git commit -m "ci: release workflow builds + publishes prebuilt WE tarball on tag"
```

---

## Task 4: Installer fast-path + fallback (imi-unify repo)

**Files:**
- Modify: `~/dev/imi-unify/sdata/subcmd-install/4.wallpaperengine.sh`
- Test: `~/dev/imi-unify/dots/.config/quickshell/ii/tests/test_wallpaperengine_prebuilt.py` (repo's test suite lives under `.../ii/tests/`)

Refactor step 5's wrapper into an `install_wrapper()` helper, add `try_prebuilt()`, and make the source path clone the repo (as today) then delegate the compile to `build-we.sh`. The download source is overridable for tests via `WE_PREBUILT_DIR` (local fixture) instead of `curl`.

- [ ] **Step 1: Write the failing test**

```python
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
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && python3 -m pytest tests/test_wallpaperengine_prebuilt.py -q`
Expected: failures (script has no `try_prebuilt`, no `WE_PREBUILT_DIR`/`WE_INSTALL_PREFIX`/`WE_NO_SOURCE_FALLBACK` support yet).

- [ ] **Step 3: Rewrite `4.wallpaperengine.sh`**

Keep the top-of-file header comment. Replace the body (from `set -euo pipefail` onward) with the structure below. Test-only env knobs: `WE_PREBUILT_DIR` (copy from a local dir instead of curl), `WE_INSTALL_PREFIX` (install wrapper under here instead of `/usr/local/bin`, and skip `sudo`), `WE_NO_SOURCE_FALLBACK` (exit nonzero instead of compiling — keeps tests offline/fast), `WE_SKIP_OPT_CHECK` (don't require `/opt/linux-wallpaperengine` to exist during the smoke test).

```bash
set -euo pipefail

[[ "${INSTALL_WE:-0}" == "1" ]] || { echo "[ImI] Wallpaper Engine: skipped."; exit 0; }

WE_REPO="${WE_REPO:-https://github.com/XephyLon/qs-wallpaperengine}"
WE_REF="${WE_REF:-v0.1.0}"                       # release tag; installer prefers the prebuilt for this tag
BUILD_DIR="${BUILD_DIR:-$HOME/.cache/immaterial-impulse/qs-wallpaperengine-build}"
PREBUILT_ROOT="${PREBUILT_ROOT:-$HOME/.cache/immaterial-impulse/prebuilt}"
PREFIX="${WE_INSTALL_PREFIX:-/usr/local/bin}"
OPT_LIBS="/opt/linux-wallpaperengine/lib:/opt/linux-wallpaperengine"

say(){ echo "[ImI] Wallpaper Engine: $*"; }
# sudo unless we're installing under a test prefix
maybe_sudo(){ if [[ "$PREFIX" == "/usr/local/bin" ]]; then sudo "$@"; else "$@"; fi; }
verlte(){ [[ "$1" == "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" ]]; }

# Install the LD_LIBRARY_PATH wrapper + `qs` symlink. $1=quickshell binary, $2=lib dir.
install_wrapper(){
  local qs_bin="$1" lib_dir="$2"
  local tmp; tmp="$(mktemp)"
  cat > "$tmp" <<WRAPPER
#!/usr/bin/env bash
# Installed by immaterial-impulse's 4.wallpaperengine.sh. Runs the WE-capable
# Quickshell build with the linux-wallpaperengine runtime libs on
# LD_LIBRARY_PATH (bundled build output + the system package's /opt install).
export LD_LIBRARY_PATH="$lib_dir:$OPT_LIBS\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$qs_bin" "\$@"
WRAPPER
  maybe_sudo install -Dm755 "$tmp" "$PREFIX/quickshell"
  maybe_sudo ln -sf "$PREFIX/quickshell" "$PREFIX/qs"
  rm -f "$tmp"
  say "installed a WE-capable quickshell wrapper to $PREFIX (shadows the distro package on PATH)."
}

# Try the prebuilt release for $WE_REF. Return 0 if installed, 1 to fall back.
try_prebuilt(){
  [[ "${WE_FORCE_SOURCE:-0}" == "1" ]] && return 1
  local arch; arch="$(uname -m)"
  [[ "$arch" == "x86_64" ]] || { say "prebuilt: arch $arch unsupported; building from source."; return 1; }
  [[ "$WE_REF" =~ ^[A-Za-z0-9._-]+$ ]] || { say "prebuilt: bad ref; building from source."; return 1; }

  local work; work="$(mktemp -d)"
  local tarball="qs-wallpaperengine-${WE_REF}-x86_64.tar.zst"
  if [[ -n "${WE_PREBUILT_DIR:-}" ]]; then
    cp "$WE_PREBUILT_DIR/$tarball" "$WE_PREBUILT_DIR/manifest.json" \
       "$WE_PREBUILT_DIR/SHA256SUMS" "$work/" 2>/dev/null \
       || { say "prebuilt: fixture incomplete; building from source."; rm -rf "$work"; return 1; }
  else
    local base="${WE_PREBUILT_BASE_URL:-$WE_REPO/releases/download}"
    curl -fsSL "$base/$WE_REF/manifest.json" -o "$work/manifest.json" 2>/dev/null \
      && curl -fsSL "$base/$WE_REF/SHA256SUMS" -o "$work/SHA256SUMS" 2>/dev/null \
      && curl -fsSL "$base/$WE_REF/$tarball"   -o "$work/$tarball"   2>/dev/null \
      || { say "prebuilt: no release for $WE_REF; building from source."; rm -rf "$work"; return 1; }
  fi

  if ! ( cd "$work" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ); then
    say "prebuilt: checksum mismatch; building from source."; rm -rf "$work"; return 1
  fi

  local qt_min host_qt
  qt_min="$(sed -n 's/.*"qt_min"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$work/manifest.json")"
  local man_arch
  man_arch="$(sed -n 's/.*"arch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$work/manifest.json")"
  [[ -z "$man_arch" || "$man_arch" == "$arch" ]] || { say "prebuilt: arch $man_arch != $arch; building from source."; rm -rf "$work"; return 1; }
  host_qt="$(pacman -Q qt6-base 2>/dev/null | awk '{print $2}')"
  if [[ -n "$qt_min" && -n "$host_qt" ]] && ! verlte "$qt_min" "$host_qt"; then
    say "prebuilt: host Qt $host_qt < build Qt $qt_min; building from source."; rm -rf "$work"; return 1
  fi

  local dest="$PREBUILT_ROOT/$WE_REF"
  rm -rf "$dest"; mkdir -p "$dest"
  tar --use-compress-program=unzstd -xf "$work/$tarball" -C "$dest" \
    || { say "prebuilt: extract failed; building from source."; rm -rf "$work" "$dest"; return 1; }
  rm -rf "$work"

  local qs_bin="$dest/bin/quickshell" lib="$dest/lib"
  [[ -x "$qs_bin" ]] || { say "prebuilt: binary missing; building from source."; return 1; }
  if [[ "${WE_SKIP_OPT_CHECK:-0}" != "1" && ! -d /opt/linux-wallpaperengine ]]; then
    say "prebuilt: /opt/linux-wallpaperengine runtime not installed; building from source."; return 1
  fi
  if ! LD_LIBRARY_PATH="$lib:$OPT_LIBS" "$qs_bin" --version >/dev/null 2>&1; then
    say "prebuilt: smoke test failed; building from source."; return 1
  fi

  install_wrapper "$qs_bin" "$lib"
  say "installed prebuilt $WE_REF (skipped the ~compile)."
  return 0
}

# Source build: clone/update the toolchain repo, then delegate the compile to
# the repo's own build-we.sh (shared with CI).
source_build(){
  if [[ "${WE_NO_SOURCE_FALLBACK:-0}" == "1" ]]; then
    say "prebuilt unavailable and source fallback disabled (test mode)."; exit 1
  fi
  say "building qs-wallpaperengine from source (this can take a while)..."
  if [[ -d "$BUILD_DIR/.git" ]]; then
    git -C "$BUILD_DIR" fetch --all --tags
    git -C "$BUILD_DIR" checkout "$WE_REF"
    git -C "$BUILD_DIR" pull --ff-only origin "$WE_REF" 2>/dev/null || true
  else
    mkdir -p "$(dirname "$BUILD_DIR")"
    git clone "$WE_REPO" "$BUILD_DIR"
    git -C "$BUILD_DIR" checkout "$WE_REF"
  fi
  local paths QS_BIN WE_LIB_DIR
  paths="$(REPO_ROOT="$BUILD_DIR" bash "$BUILD_DIR/scripts/build-we.sh")"
  eval "$paths"
  [[ -x "$QS_BIN" ]] || { say "build finished but $QS_BIN missing. Aborting." >&2; exit 1; }
  install_wrapper "$QS_BIN" "$WE_LIB_DIR"
}

if try_prebuilt; then exit 0; fi
source_build
```

- [ ] **Step 4: Run the tests, verify PASS**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && python3 -m pytest tests/test_wallpaperengine_prebuilt.py -q`
Expected: 4 passed.

- [ ] **Step 5: Run the existing WE test + full suite (no regressions)**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && python3 -m pytest tests/test_wallpaper_engine.py -q && ./tests/run_tests.sh`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
cd ~/dev/imi-unify
git add sdata/subcmd-install/4.wallpaperengine.sh \
        dots/.config/quickshell/ii/tests/test_wallpaperengine_prebuilt.py
git commit -m "feat(installer): prebuilt WE fast-path with verified download + source fallback"
```

---

## Task 5: Docs + release note (both repos)

**Files:**
- Create: `~/dev/qs-wallpaperengine/docs/cutting-a-release.md`
- Modify: `~/dev/imi-unify/docs/superpowers/plans/2026-07-24-prebuilt-wallpaperengine.md` (mark status), `~/dev/imi-unify/.github/README.md` (one line under install: "WE installs a verified prebuilt when available, else compiles").

- [ ] **Step 1: Write `cutting-a-release.md`**

```markdown
# Cutting a qs-wallpaperengine release

1. Ensure `main` builds: `REPO_ROOT="$PWD" bash scripts/build-we.sh` then run
   the built binary with the WE libs on `LD_LIBRARY_PATH`.
2. Tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. `release.yml` builds in an Arch container, packages
   `qs-wallpaperengine-vX.Y.Z-x86_64.tar.zst` + `manifest.json` + `SHA256SUMS`,
   smoke-tests the binary, and publishes the GitHub Release.
4. Point imi-unify at it: set `WE_REF` default to `vX.Y.Z` in
   `sdata/subcmd-install/4.wallpaperengine.sh`. Installs now fetch the prebuilt;
   any checksum/arch/Qt/smoke failure falls back to a local compile.
```

- [ ] **Step 2: Update the README install line + this plan's status header.**

- [ ] **Step 3: Commit (each repo separately)**

```bash
cd ~/dev/qs-wallpaperengine && git add docs/cutting-a-release.md \
  && git commit -m "docs: how to cut a prebuilt release"
cd ~/dev/imi-unify && git add .github/README.md \
  docs/superpowers/plans/2026-07-24-prebuilt-wallpaperengine.md \
  && git commit -m "docs: note verified-prebuilt WE install path"
```

---

## Verification (whole feature)

- Task 1-3 (qs-wallpaperengine): the three `test_*.sh` pass locally. The real compile + publish is exercised by `release.yml` on `workflow_dispatch` — run it once manually before relying on it; confirm the Release has all three assets and the smoke-test step is green.
- Task 4 (installer): `test_wallpaperengine_prebuilt.py` (4 cases: happy path, tamper→fallback, arch mismatch→fallback, smoke fail→fallback) + no regression in `test_wallpaper_engine.py` and `run_tests.sh`.
- Manual end-to-end on this machine: with a real published tag, run `INSTALL_WE=1 WE_REF=vX.Y.Z bash sdata/subcmd-install/4.wallpaperengine.sh` and confirm it installs in seconds and `qs --version` works; then force the fallback with `WE_FORCE_SOURCE=1` and confirm it still compiles+installs. Time both.

## Commit strategy

One commit per task as shown (five feature/docs commits total, split across the two repos). Do NOT push, tag, or create releases until the user explicitly asks. qs-wallpaperengine commits touch only the files this plan adds — leave the user's other dirty files alone.

## Out of scope (unchanged from the spec)

Arch binary package / pacman repo (Option B); non-x86_64 prebuilts; ccache (fold into `build-we.sh` opportunistically if trivial, not a blocker).
