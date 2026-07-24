# Prebuilt qs-wallpaperengine — Design

**Status:** draft 2026-07-24. Next step: user review → implementation plan.

## Goal

Cut first-time install time by shipping a **prebuilt** patched Quickshell +
linux-wallpaperengine, so `4.wallpaperengine.sh` downloads a verified binary
tarball (seconds) instead of compiling two C++ upstreams (~5-40 min depending
on cores). Compiling from source stays as an automatic fallback — no system is
worse off than today.

## Why this is the bottleneck (measured 2026-07-24)

- `sdata/subcmd-install/4.wallpaperengine.sh` compiles **patched Quickshell**
  (11MB binary — the dominant cost, a large Qt/C++ build) and
  **linux-wallpaperengine**'s own sources. The bundled `.so`s in
  `build/output` (libcef, libEGL, libGLESv2, libvk_swiftshader) are prebuilt
  downloads, not compiled.
- No CI, no releases, no ccache on `XephyLon/qs-wallpaperengine` today.
- Repeat installs are already incremental (BUILD_DIR kept under
  `~/.cache/immaterial-impulse`, survives the config wipes). **Only the fresh
  first build hurts** — that's what this removes.

## Why a prebuilt native binary is safe here

- Qt guarantees C++ ABI stability across 6.x minors, so a binary built on one
  Qt 6 minor runs on a newer one. Other links (wayland/pipewire/pam/polkit) are
  ABI-stable.
- The WE runtime `.so`s are **self-contained** (bundled CEF/EGL/swiftshader) —
  nothing to ABI-match against the host.
- Residual risk (arch mismatch, host Qt *older* than build Qt, non-glibc
  distro) is caught by a runtime smoke test + version check, which falls back
  to the source build. So the fast path is strictly opt-in-when-it-works.

Scope note: the prebuilt replaces only the **compile** of quickshell + the WE
lib. The system `linux-wallpaperengine-git` package (`/opt/linux-wallpaperengine`,
`/opt/linux-wallpaperengine/lib`) remains a prerequisite exactly as today — the
wrapper still puts those on `LD_LIBRARY_PATH`.

## Components

### 1. Release CI (`XephyLon/qs-wallpaperengine`, `.github/workflows/release.yml`)
- Trigger: push of a `v*` tag (and `workflow_dispatch` for manual runs).
- Runner: `ubuntu-latest` hosting an `archlinux:latest` container (matches the
  primary target distro + a current Qt, mirrors the stock
  `immaterial-impulse-quickshell-git` toolchain).
- Steps:
  1. `pacman -Syu` the build deps (the same set
     `sdata/dist-arch/install-deps.sh` installs for the shell build: qt6,
     cmake, ninja, wayland, pipewire, pam, polkit, jemalloc, etc. — enumerated
     in the plan).
  2. Run the **exact build** `4.wallpaperengine.sh` already does — factored
     into a shared `scripts/build-we.sh` in the qs-wallpaperengine repo so CI
     and the installer's source-fallback run identical commands (no drift).
  3. Bundle into `qs-wallpaperengine-<tag>-x86_64.tar.zst`:
     - `bin/quickshell` (the build2 binary),
     - `lib/*.so*` (everything from `build/output`),
     - `manifest.json`: `{ schema, version(tag), commit, qt_version,
       qt_min (build qt6-base ver), arch, built_at, files:[...] }`.
  4. Compute `SHA256SUMS` over the tarball + manifest.
  5. `gh release create <tag>` uploading the tarball, `manifest.json`, and
     `SHA256SUMS`.

### 2. Shared build script (`qs-wallpaperengine/scripts/build-we.sh`)
Extract the fetch/bootstrap/cmake/ninja logic currently inline in
`4.wallpaperengine.sh` into one script the installer sources for its fallback
and CI calls directly. Single source of truth for the build; the installer's
step 4 shrinks to "try prebuilt, else `build-we.sh`".

### 3. Installer fast-path (`sdata/subcmd-install/4.wallpaperengine.sh`)
New order (still gated by `INSTALL_WE=1`):
1. Resolve target ref/tag (`WE_REF`, defaulting to the release tag once one
   exists; commit pin stays valid for source builds).
2. Unless `WE_FORCE_SOURCE=1`: `curl` the release's `manifest.json` +
   `SHA256SUMS` + tarball for this tag.
   - Skip to source if: no matching release, `uname -m != x86_64`,
     `manifest.arch` mismatch, or host `qt6-base` version < `manifest.qt_min`.
3. Verify `sha256sum -c SHA256SUMS`. Mismatch → **hard fail to source build**
   (never install unverified bytes).
4. Extract to `~/.cache/immaterial-impulse/prebuilt/<tag>/`.
5. **Smoke test:** run the extracted binary through a temp wrapper with the
   right `LD_LIBRARY_PATH` (`prebuilt/<tag>/lib` + the `/opt` dirs); require
   `quickshell --version` (or `--help`) to exit 0. Any failure → source build.
6. Install the same `/usr/local/bin/quickshell` wrapper + `qs` symlink as today,
   with `LD_LIBRARY_PATH` pointed at the extracted `lib/` instead of the build
   dir. Identical wrapper contract, different lib path.
7. On any fast-path failure, fall through to `build-we.sh` — same result as
   today, just slower. Log which path was taken.

### 4. Tagging / release flow (docs)
- `qs-wallpaperengine` gets semver tags (`v0.1.0`…). Pushing a tag builds+publishes.
- imi-unify's `WE_REF` moves from the raw commit `a721ef1` to the release tag;
  the installer prefers the prebuilt for that tag and only compiles on miss.

## Security

- Downloads verified by `sha256sum -c` before anything is executed or installed;
  verification failure aborts the fast path (falls back to a local compile).
- No `bash -c` splicing of remote data: tag/arch/version are validated
  (`^[A-Za-z0-9._-]+$` / `x86_64`) and passed as argv, per the injection
  hardening in commit 75ef1aec.
- CI publishes over authenticated `gh` in the repo's own Actions; no third-party
  artifact host.

## Testing

- **CI dry-run:** `workflow_dispatch` produces a tarball whose `manifest.json`
  and `SHA256SUMS` validate; a job step extracts + smoke-tests the binary inside
  the Arch container before the release is cut.
- **Installer (bats/python in a temp HOME):** assert the fast-path
  (a) verifies a good checksum and installs the wrapper pointing at the
  extracted lib dir; (b) rejects a tampered tarball and falls back;
  (c) falls back on arch/Qt mismatch and on smoke-test failure. Network calls
  stubbed with a local fixture release dir.
- **Manual:** one real fresh install on this machine timing prebuilt vs source.

## Files

- Create: `qs-wallpaperengine/.github/workflows/release.yml`,
  `qs-wallpaperengine/scripts/build-we.sh`.
- Modify: `sdata/subcmd-install/4.wallpaperengine.sh` (fast-path + source
  fallback via the shared script), `WE_REF` default.
- Docs: this spec + a short "cutting a release" note in the qs-wallpaperengine
  README.

## Out of scope

- Option B (Arch binary package / hosted pacman repo) — revisit if Arch-native
  packaging is wanted later.
- Non-x86_64 arches — source build only, until there's demand.
- ccache — cheap add-on to `build-we.sh` for faster *fallback* rebuilds; fold
  in during implementation if trivial, not a blocker.
