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
#   - The built binary carries a RUNPATH to that output dir, so it resolves
#     those libs unaided. We still install a small wrapper at
#     /usr/local/bin/quickshell (it execs the real binary in the cache build
#     dir and sets the Qt render loop), plus a `qs` symlink to it. The wrapper
#     deliberately does NOT export LD_LIBRARY_PATH: it is inherited by every
#     app the shell launches, and those dirs carry CEF's own libEGL/libGLESv2,
#     which shadowed the system ones and crashed Firefox at startup. /usr/local/bin is first on PATH ahead of
#     /usr/bin on virtually every distro, so this shadows the distro package's
#     `qs`/`quickshell` (e.g. immaterial-impulse-quickshell-git) without ever
#     touching a package-manager-owned file.
set -euo pipefail

[[ "${INSTALL_WE:-0}" == "1" ]] || { echo "[ImI] Wallpaper Engine: skipped."; exit 0; }

WE_REPO="${WE_REPO:-https://github.com/XephyLon/qs-wallpaperengine}"
WE_REF="${WE_REF:-v0.2.6}"                       # release tag, so installs take the PREBUILT fast path; any checksum /
                                                 # arch / Qt-too-old / smoke-test failure falls back to a source build, as
                                                 # does a tag whose release has not published yet. Whatever this points at
                                                 # MUST be >= 40427cf, the commit that added
                                                 # scripts/build-we.sh (source_build() runs it, and eval's its stdout —
                                                 # 71dea54 made that eval-safe); a11e083 additionally carries the
                                                 # bootstrap patch that stops Quickshell rescanning every .desktop file
                                                 # on parent-dir churn (multi-second QV4 GC freezes per wallpaper switch
                                                 # without it), and 6cb13cd adds the frame-fence glFlush (without it a
                                                 # VIDEO wallpaper throttles the whole shell to the video's frame rate).
                                                 # v0.1.0 (7e58913) is REQUIRED for a live wallpaper to idle when, and only
                                                 # when, it is behind a fullscreen window: it passes
                                                 # --fullscreen-pause-only-active to the embedded linux-wallpaperengine,
                                                 # whose detector otherwise counts EVERY fullscreen toplevel - output,
                                                 # workspace and visibility are not part of the test - and halts the render
                                                 # loop (pausing mpv with it) for a game parked on a workspace the user has
                                                 # left. The pin sat at fd5715e, so every install carried that freeze.
                                                 # v0.2.0 adds WallpaperEngineSurface.failed, which Background.qml reads to
                                                 # fall back to the static image when the renderer cannot draw at all -
                                                 # that read is inert on any older build, so this is the floor for the
                                                 # fallback to do anything. v0.2.0 is also the first release whose CI
                                                 # actually published assets: v0.1.0 built for 34 minutes and then died on
                                                 # `gh release create`, so the prebuilt path silently fell back to a source
                                                 # compile on every install.
                                                 # v0.2.1 stops a wallpaper that wedged inside WE's setup() from having
                                                 # its WeThread freed while the detached thread is still running in it -
                                                 # the replacement thread is allocated at the same size moments later and
                                                 # lands on that address as often as not, at which point the dead
                                                 # wallpaper publishes its texture and fence into the live one's state.
                                                 # v0.2.2 REPLACES the v0.1.0 arrangement described above. WE's detector
                                                 # turned out to be output-blind - its toplevel output-enter/leave handlers
                                                 # are empty stubs, so its count is process-wide while the shell runs one
                                                 # renderer per monitor, and a game fullscreened on one monitor paused the
                                                 # wallpapers on all of them. No spelling of the flag fixes that, so the
                                                 # embed now passes --no-fullscreen-pause and the SHELL decides, per output,
                                                 # through WallpaperEngineSurface.occluded.
                                                 #
                                                 # That makes this pin and the shell a matched pair: on v0.2.2 a shell that
                                                 # never sets `occluded` gets NO fullscreen pause at all. Background.qml
                                                 # sets it (via WallpaperEngineLayer's `covered`), guarded by a property
                                                 # check so it stays inert on older builds - but do not move this pin
                                                 # backwards past v0.2.2 without checking that guard still holds, and do not
                                                 # ship a shell without that binding against this pin.
                                                 # v0.2.2 also fixes a fence race (glWaitSync could name a deleted fence,
                                                 # which is GL_INVALID_VALUE and therefore no wait at all - a torn frame
                                                 # with nothing in any log) and a stale scene-graph node surviving a project
                                                 # switch after its GL texture was deleted.
                                                 # Cutting the next release: qs-wallpaperengine/docs/cutting-a-release.md.
BUILD_DIR="${BUILD_DIR:-$HOME/.cache/immaterial-impulse/qs-wallpaperengine-build}"
PREBUILT_ROOT="${PREBUILT_ROOT:-$HOME/.cache/immaterial-impulse/prebuilt}"
PREFIX="${WE_INSTALL_PREFIX:-/usr/local}"        # install root; binaries land in $PREFIX/bin (prod: /usr/local/bin, shadows distro qs)
OPT_LIBS="/opt/linux-wallpaperengine/lib:/opt/linux-wallpaperengine"

say(){ echo "[ImI] Wallpaper Engine: $*"; }
# sudo unless we're installing under a test prefix
maybe_sudo(){ if [[ "$PREFIX" == "/usr/local" ]]; then sudo "$@"; else "$@"; fi; }
verlte(){ [[ "$1" == "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" ]]; }

# Stamp recording which WE_REF the currently-installed wrapper was built/
# installed from, plus the binary it points at. Lets a re-run (an update where
# the pin didn't change) skip the whole fetch+build - previously EVERY re-run
# recompiled from scratch (build-we.sh rm -rf's its build dir), costing
# 5-40 min for a no-op. WE_FORCE_REBUILD=1 overrides the skip.
STAMP_FILE="${WE_STAMP_FILE:-$HOME/.cache/immaterial-impulse/we-installed-ref}"

write_stamp(){ # $1 = installed ref, $2 = qs binary path, $3 = WE lib dir
  mkdir -p "$(dirname "$STAMP_FILE")"
  printf '%s %s %s\n' "$1" "$2" "${3:-}" > "$STAMP_FILE"
}

up_to_date(){
  [[ "${WE_FORCE_REBUILD:-0}" == "1" ]] && return 1
  [[ -f "$STAMP_FILE" ]] || return 1
  # Three variables for a three-field stamp. `read` puts every remaining field
  # into the LAST name, so `read -r ref bin` left bin holding "<binary> <libdir>"
  # once write_stamp started recording the lib dir - a string that is never an
  # executable, so the -x below could not pass and this function could not return
  # 0. The skip was dead: every re-run paid the full fetch+build it exists to
  # avoid. The main block below already reads three, which is why the bug hid -
  # the code after the gate was correct, the gate just never opened.
  local ref bin lib
  read -r ref bin lib < "$STAMP_FILE" || return 1
  [[ "$ref" == "$WE_REF" ]] || return 1
  [[ -x "$bin" ]] || return 1                    # build output still on disk
  [[ -x "$PREFIX/bin/quickshell" ]] || return 1  # wrapper still installed
  return 0
}

# Make the binary resolve its WE libs on its own, so the wrapper does not have
# to export LD_LIBRARY_PATH. Exporting it was a real bug: the variable is
# inherited by every process the shell spawns, so CEF's bundled libEGL.so /
# libGLESv2.so in the WE lib dirs shadowed the system ones for every app
# launched from the launcher. Firefox picked them up and died during GPU init
# ~0.5s in, reporting StartupCrash with no useful message.
#
# The build already bakes a RUNPATH pointing at build/output, so in practice
# nothing is needed. Repair it with patchelf only if something is genuinely
# unresolved, and fall back to the old export as a last resort rather than
# shipping a shell that will not start. Returns 0 when the binary is
# self-sufficient.
libs_resolve_standalone(){
  local qs_bin="$1"
  ! env -u LD_LIBRARY_PATH ldd "$qs_bin" 2>/dev/null | grep -q "not found"
}

# Rewrite one ELF's RUNPATH. $1=file, $2=new RUNPATH. Returns 0 on success.
#
# patchelf rewrites in place, and the kernel refuses to write to a running
# executable (ETXTBSY). The shell IS the binary being repaired, and Settings >
# Update Dots runs the installer *from* the shell - so in the one path a user
# actually takes, the target was always executing and this always failed. The
# same hazard applies to the bundled .so files, which the running process has
# mapped.
#
# Patch a copy and rename over the original instead. rename(2) swaps the
# directory entry; the running process keeps the inode it already opened and is
# unaffected, and the next launch picks up the repaired file. The temporary
# lives beside the target so the rename stays on one filesystem - mv across
# filesystems is copy-then-unlink, which is neither atomic nor safe against a
# concurrent exec.
set_runpath(){
  local target="$1" rpath="$2" tmp
  tmp="$(mktemp "${target}.patchelf.XXXXXX")" || return 1
  if cp -p "$target" "$tmp" \
     && patchelf --set-rpath "$rpath" "$tmp" \
     && mv -f "$tmp" "$target"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

ensure_standalone_libs(){
  local qs_bin="$1" lib_dir="$2"
  libs_resolve_standalone "$qs_bin" && return 0
  if command -v patchelf >/dev/null 2>&1; then
    local rp; rp="$(patchelf --print-rpath "$qs_bin" 2>/dev/null || true)"
    if set_runpath "$qs_bin" "$lib_dir:$OPT_LIBS${rp:+:$rp}"; then
      say "baked the WE runtime lib dirs into the binary's RUNPATH."
    else
      # Surface the reason rather than discarding it - the previous silence is
      # what made this look like a missing dependency for so long.
      say "could not repair the binary's RUNPATH with patchelf."
    fi

    # DT_RUNPATH is NOT transitive. The executable's RUNPATH resolves its own
    # direct dependencies and nothing else: liblinux-wallpaperengine-lib.so's
    # own needs (libcef.so beside it, libkissfft-float.so from the /opt runtime)
    # are searched using *that library's* RUNPATH, which is the builder's
    # directory and exists nowhere. So repairing only the binary left the shell
    # still unable to start unaided, and the LD_LIBRARY_PATH fallback - which IS
    # transitive, and is exactly why it worked where the RUNPATH did not - stayed
    # in the wrapper.
    #
    # $ORIGIN first so a library finds its siblings wherever the prebuilt tree
    # is unpacked, then the /opt runtime for what is not bundled.
    local so
    for so in "$lib_dir"/*.so*; do
      [[ -f "$so" ]] || continue
      libs_resolve_standalone "$so" && continue
      local so_rp; so_rp="$(patchelf --print-rpath "$so" 2>/dev/null || true)"
      set_runpath "$so" "\$ORIGIN:$OPT_LIBS${so_rp:+:$so_rp}" \
        || say "could not repair $(basename "$so")'s RUNPATH."
    done
  else
    say "patchelf not present; cannot repair the binary's RUNPATH."
  fi
  libs_resolve_standalone "$qs_bin"
}

# Install the wrapper + `qs` symlink. $1=quickshell binary, $2=lib dir.
install_wrapper(){
  local qs_bin="$1" lib_dir="$2"
  local ld_line=""
  if ensure_standalone_libs "$qs_bin" "$lib_dir"; then
    say "binary resolves its WE libs unaided; not exporting LD_LIBRARY_PATH."
  else
    say "WARNING: binary still needs LD_LIBRARY_PATH. Exporting it as a fallback -"
    say "         apps launched from the shell may load CEF's libEGL/libGLESv2"
    say "         instead of the system ones."
    # Only advise installing patchelf when it is actually missing. Saying it
    # unconditionally sent someone to install a package they already had, and
    # then to re-run, which could not have helped either.
    if command -v patchelf >/dev/null 2>&1; then
      say "         patchelf is installed but could not repair the binary; see above."
    else
      say "         Install patchelf and re-run to fix."
    fi
    ld_line="export LD_LIBRARY_PATH=\"$lib_dir:$OPT_LIBS\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""
  fi
  local tmp; tmp="$(mktemp)"
  cat > "$tmp" <<WRAPPER
#!/usr/bin/env bash
# Installed by immaterial-impulse's 4.wallpaperengine.sh. Runs the WE-capable
# Quickshell build. The binary carries its own RUNPATH for the
# linux-wallpaperengine runtime libs, so nothing is put on LD_LIBRARY_PATH:
# that variable is inherited by every app the shell launches, and the WE lib
# dirs contain CEF's own libEGL/libGLESv2, which crashed Firefox on startup.
$ld_line
# Force Qt's THREADED render loop. On NVIDIA/Wayland Qt otherwise auto-selects
# the BASIC loop, which renders QML on the GUI thread; an embedded WE *video*
# wallpaper (mpv/CUDA) then blocks that thread in glClientWaitSync/endFrame for
# many seconds on every wallpaper switch (its surface teardown saturates the
# shared GL context), freezing QML timers so the wallpaper-switch transition
# animation hangs (~11s per switch, measured). Threaded moves rendering to the
# QSGRenderThread, keeping animations responsive (teardown hitch drops to
# <1s). Verified: WE still renders correctly under threaded on NVIDIA here.
export QSG_RENDER_LOOP=threaded
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
  write_stamp "$WE_REF" "$qs_bin" "$lib"
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
  write_stamp "$WE_REF" "$QS_BIN" "$WE_LIB_DIR"
}

if up_to_date; then
  # The build is current, but ALWAYS rewrite the wrapper before exiting.
  # Skipping it meant a wrapper-only fix could never reach an existing
  # install: the stamp matched, the script exited, and the old wrapper stayed
  # on disk. That is exactly how the LD_LIBRARY_PATH leak survived an update
  # and a restart - re-running the installer looked like a no-op. Rewriting a
  # small file is cheap; the expensive fetch/build is what the stamp guards.
  read -r _stamp_ref _stamp_bin _stamp_lib < "$STAMP_FILE"
  # Stamps written before the lib dir was recorded have no third field.
  : "${_stamp_lib:=$BUILD_DIR/build/linux-wallpaperengine/build/output}"
  say "already installed at $WE_REF; refreshing the wrapper and skipping the rebuild."
  install_wrapper "$_stamp_bin" "$_stamp_lib"
  write_stamp "$WE_REF" "$_stamp_bin" "$_stamp_lib"
  exit 0
fi
if try_prebuilt; then exit 0; fi
source_build
