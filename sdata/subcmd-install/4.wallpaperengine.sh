#!/usr/bin/env bash
# 4.wallpaperengine.sh — OPTIONAL. Builds the patched Quickshell (carrying the
# Quickshell.WallpaperEngine module) + linux-wallpaperengine, and installs it so
# `qs`/`quickshell` on PATH is the WE-capable build. No-op unless INSTALL_WE=1.
#
# Unlike the other numbered subcmd-install/*.sh steps, this one is meant to be
# RUN (`bash 4.wallpaperengine.sh`), not sourced: it's self-contained and uses
# `exit 0` for the skip path, which would blow up the caller if sourced.
#
# What this does, and why, per XephyLon/qs-wallpaperengine (read at
# implementation time, see ~/dev/qs-wallpaperengine README.md/bootstrap.sh/
# launch-shell.sh):
#   - bootstrap.sh only clones+patches the two upstreams (linux-wallpaperengine
#     and Quickshell) and prints the cmake invocations as COMMENTS for manual
#     iteration ("Status: Scaffold only") — it does not build anything itself.
#     So this script runs those documented cmake steps itself.
#   - The actual working Quickshell build directory (confirmed against
#     launch-shell.sh, the real runtime launcher) is `build2`, not the `build`
#     dir bootstrap.sh's comments name — a fresh configure-with-all-flags-on
#     dir was needed after toggling service plugins broke an existing one
#     (see bootstrap.sh's own comment on this).
#   - linux-wallpaperengine's build additionally bundles a handful of runtime
#     libs (its own libEGL/libGLESv2, CEF/libcef, libvk_swiftshader) into its
#     `build/output` directory alongside liblinux-wallpaperengine-lib.so.
#     `launch-shell.sh` shows the patched quickshell binary needs all of that
#     on LD_LIBRARY_PATH to run: `build/linux-wallpaperengine/build/output`,
#     plus `/opt/linux-wallpaperengine/lib` and `/opt/linux-wallpaperengine`
#     (the system linux-wallpaperengine-git package's install dirs).
#   - Because of that runtime lib dependency, we do NOT just copy the raw
#     `quickshell` binary to /usr/local/bin (it would fail to start without
#     LD_LIBRARY_PATH). We install a small wrapper at /usr/local/bin/quickshell
#     that sets LD_LIBRARY_PATH and execs the real binary in the cache build
#     dir, plus a `qs` symlink to it. /usr/local/bin is first on PATH ahead of
#     /usr/bin on virtually every distro, so this shadows the distro package's
#     `qs`/`quickshell` (e.g. immaterial-impulse-quickshell-git) without ever
#     touching a package-manager-owned file.
set -euo pipefail

[[ "${INSTALL_WE:-0}" == "1" ]] || { echo "[ImI] Wallpaper Engine: skipped."; exit 0; }

WE_REPO="${WE_REPO:-https://github.com/XephyLon/qs-wallpaperengine}"
WE_REF="${WE_REF:-v0.1.0}"                       # release tag; installer prefers the prebuilt for this tag
BUILD_DIR="${BUILD_DIR:-$HOME/.cache/immaterial-impulse/qs-wallpaperengine-build}"
PREBUILT_ROOT="${PREBUILT_ROOT:-$HOME/.cache/immaterial-impulse/prebuilt}"
PREFIX="${WE_INSTALL_PREFIX:-/usr/local}"        # install root; binaries land in $PREFIX/bin (prod: /usr/local/bin, shadows distro qs)
OPT_LIBS="/opt/linux-wallpaperengine/lib:/opt/linux-wallpaperengine"

say(){ echo "[ImI] Wallpaper Engine: $*"; }
# sudo unless we're installing under a test prefix
maybe_sudo(){ if [[ "$PREFIX" == "/usr/local" ]]; then sudo "$@"; else "$@"; fi; }
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
  maybe_sudo install -Dm755 "$tmp" "$PREFIX/bin/quickshell"
  maybe_sudo ln -sf "$PREFIX/bin/quickshell" "$PREFIX/bin/qs"
  rm -f "$tmp"
  say "installed a WE-capable quickshell wrapper to $PREFIX/bin (shadows the distro package on PATH)."
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
