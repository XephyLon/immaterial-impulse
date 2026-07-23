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

echo "[ImI] Wallpaper Engine: building qs-wallpaperengine (this can take a while)..."

WE_REPO="${WE_REPO:-https://github.com/XephyLon/qs-wallpaperengine}"
WE_REF="${WE_REF:-dc3620f}"                     # pinned qs-wallpaperengine rev; bump to its v0.1.0 tag once released
BUILD_DIR="${BUILD_DIR:-$HOME/.cache/immaterial-impulse/qs-wallpaperengine-build}"
JOBS="${WE_BUILD_JOBS:-$(nproc)}"

# --- 1. Fetch/update the qs-wallpaperengine toolchain repo -----------------
# Reuse an existing clone across re-runs instead of `rm -rf`ing it: the nested
# build/ dirs it creates below (linux-wallpaperengine + Quickshell) are
# themselves reused by bootstrap.sh (its clone_at() only clones if missing),
# so keeping BUILD_DIR around lets ninja/make do incremental rebuilds on
# repeat installs instead of rebuilding both upstreams from scratch every time.
if [[ -d "$BUILD_DIR/.git" ]]; then
  git -C "$BUILD_DIR" fetch --all --tags
  git -C "$BUILD_DIR" checkout "$WE_REF"
  git -C "$BUILD_DIR" pull --ff-only origin "$WE_REF" 2>/dev/null || true
else
  mkdir -p "$(dirname "$BUILD_DIR")"
  git clone "$WE_REPO" "$BUILD_DIR"
  git -C "$BUILD_DIR" checkout "$WE_REF"
fi

cd "$BUILD_DIR"

# --- 2. Clone+patch both upstreams (per bootstrap.sh) -----------------------
bash ./bootstrap.sh

WE_SRC="$BUILD_DIR/build/linux-wallpaperengine"
QS_SRC="$BUILD_DIR/build/quickshell"

# bootstrap.sh exports these for its own (commented-out) cmake invocations;
# re-export them here since that export dies with bootstrap.sh's subshell.
export WALLPAPERENGINE_INCLUDE_DIR="$WE_SRC/src"
export WALLPAPERENGINE_SRC="$WE_SRC/src"

# --- 3. Build linux-wallpaperengine (the FBO-driver lib) --------------------
# Commands per bootstrap.sh's [1/4] section (commented there pending manual
# TODO iteration on the FBO driver; run for real here).
cmake -S "$WE_SRC" -B "$WE_SRC/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$WE_SRC/build" -j"$JOBS"

# --- 4. Build the patched Quickshell -----------------------------------
# Commands per bootstrap.sh's [3/4] section. Configured into `build2`, not
# `build`: see the note at the top of this file for why. All the service
# plugins end4-pC's shell.qml needs are turned on in this one fresh configure.
cmake -S "$QS_SRC" -B "$QS_SRC/build2" -DCMAKE_BUILD_TYPE=Release \
  -DWALLPAPERENGINE_INCLUDE_DIR="$WALLPAPERENGINE_INCLUDE_DIR" \
  -DSERVICE_MPRIS=ON -DSERVICE_NOTIFICATIONS=ON -DSERVICE_PAM=ON \
  -DSERVICE_PIPEWIRE=ON -DSERVICE_POLKIT=ON -DSERVICE_STATUS_NOTIFIER=ON \
  -DSERVICE_UPOWER=ON -DBLUETOOTH=ON
cmake --build "$QS_SRC/build2" -j"$JOBS"

QS_BIN="$QS_SRC/build2/src/quickshell"
WE_LIB_DIR="$WE_SRC/build/output"

if [[ ! -x "$QS_BIN" ]]; then
  echo "[ImI] Wallpaper Engine: build finished but $QS_BIN is missing/not executable. Aborting install." >&2
  exit 1
fi

# --- 5. Install a wrapper that shadows the distro quickshell/qs on PATH -----
# See the top-of-file note: a bare binary copy would miss the WE runtime libs
# (own libEGL/libGLESv2/libcef/libvk_swiftshader in build/output, plus the
# system linux-wallpaperengine-git package's /opt install), so LD_LIBRARY_PATH
# has to be set at launch time. Matches launch-shell.sh's env exactly.
WRAPPER_TMP="$(mktemp)"
cat > "$WRAPPER_TMP" <<WRAPPER
#!/usr/bin/env bash
# Installed by immaterial-impulse's 4.wallpaperengine.sh. Runs the
# WE-capable Quickshell build from $BUILD_DIR with the linux-wallpaperengine
# runtime libs on LD_LIBRARY_PATH (own build output + the system package's
# /opt install), then execs it with whatever args it was called with.
export LD_LIBRARY_PATH="$WE_LIB_DIR:/opt/linux-wallpaperengine/lib:/opt/linux-wallpaperengine\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$QS_BIN" "\$@"
WRAPPER
sudo install -Dm755 "$WRAPPER_TMP" /usr/local/bin/quickshell
sudo ln -sf /usr/local/bin/quickshell /usr/local/bin/qs
rm -f "$WRAPPER_TMP"

echo "[ImI] Wallpaper Engine: installed a WE-capable quickshell wrapper to /usr/local/bin (shadows the distro package on PATH)."
