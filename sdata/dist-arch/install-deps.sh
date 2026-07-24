# This script is meant to be sourced.
# It's not for directly running.

install-yay(){
  x sudo pacman -S --needed --noconfirm base-devel
  x git clone https://aur.archlinux.org/yay-bin.git /tmp/buildyay
  x cd /tmp/buildyay
  x makepkg -o
  x makepkg -se
  x makepkg -i --noconfirm
  x cd ${REPO_ROOT}
  rm -rf /tmp/buildyay
}

remove_deprecated_dependencies(){
  printf "${STY_CYAN}[$0]: Removing deprecated dependencies:${STY_RST}\n"
  local list=()
  list+=(immaterial-impulse-{microtex,pymyc-aur,oneui4-icons-git})
  list+=(hyprland-qtutils)
  list+=({quickshell,hyprutils,hyprpicker,hyprlang,hypridle,hyprland-qt-support,hyprland-qtutils,hyprlock,xdg-desktop-portal-hyprland,hyprcursor,hyprwayland-scanner,hyprland}-git)
  list+=(matugen-bin)
  for i in ${list[@]};do try sudo pacman --noconfirm -Rdd $i;done
}
# NOTE: `implicitize_old_dependencies()` was for the old days when we just switch from dependencies.conf to local PKGBUILDs.
# However, let's just keep it as references for other distros writing their `sdata/dist-<OS_GROUP_ID>/install-deps.sh`, if they need it.
implicitize_old_dependencies(){
# Convert old dependencies to non explicit dependencies so that they can be orphaned if not in meta packages
  remove_bashcomments_emptylines ./sdata/dist-arch/previous_dependencies.conf ./cache/old_deps_stripped.conf
  readarray -t old_deps_list < ./cache/old_deps_stripped.conf
  pacman -Qeq > ./cache/pacman_explicit_packages
  readarray -t explicitly_installed < ./cache/pacman_explicit_packages

  echo "Attempting to set previously explicitly installed deps as implicit..."
  for i in "${explicitly_installed[@]}"; do for j in "${old_deps_list[@]}"; do
    [ "$i" = "$j" ] && yay -D --asdeps "$i"
  done; done

  return 0
}

#####################################################################################
if ! command -v pacman >/dev/null 2>&1; then
  printf "${STY_RED}[$0]: pacman not found, it seems that the system is not ArchLinux or Arch-based distros. Aborting...${STY_RST}\n"
  exit 1
fi

# Keep makepkg from resetting sudo credentials
if [[ -z "${PACMAN_AUTH:-}" ]]; then
  export PACMAN_AUTH="sudo"
fi

showfun remove_deprecated_dependencies
v remove_deprecated_dependencies

# Issue #363
# Non-interactive runs (ask=false, e.g. the TUI's quiet mode) must not stop on
# pacman's own "Proceed? [Y/n]" — add --noconfirm there, mirroring the pattern
# used for the local-pkgbuild installs below.
syuflags=""
$ask || syuflags="--noconfirm"
case $SKIP_SYSUPDATE in
  true) true;;
  *) v sudo pacman -Syu $syuflags;;
esac

# Use yay. Because paru does not support cleanbuild.
# Also see https://wiki.hyprland.org/FAQ/#how-do-i-update
if ! command -v yay >/dev/null 2>&1;then
  echo -e "${STY_YELLOW}[$0]: \"yay\" not found.${STY_RST}"
  showfun install-yay
  v install-yay
fi

showfun implicitize_old_dependencies
v implicitize_old_dependencies

# https://github.com/end-4/dots-hyprland/issues/581
# yay -Bi is kinda hit or miss, instead cd into the relevant directory and manually source and install deps
install-local-pkgbuild() {
  local location=$1
  local installflags=$2

  x pushd $location

  # Fresh per-package metadata: `source` does not clear arrays a previous
  # PKGBUILD set, so a package that omits `replaces` would inherit the last
  # one's. Unset it first so the supersede loop below only ever sees the current
  # package's own value.
  unset replaces
  source ./PKGBUILD

  # Idempotent local install: if this exact version is already installed and we
  # were asked for --needed, skip the rebuild+reinstall. Besides saving time,
  # this stops a broken *rebuild* of an already-installed package (e.g. a pinned
  # commit that no longer builds against a newer toolchain) from aborting the
  # whole install — the working installed copy is kept. Version-based pkgs whose
  # $pkgver comes from a pkgver() function won't match here and just build, which
  # is the safe default.
  local _inst
  _inst="$(pacman -Q "$pkgname" 2>/dev/null | awk '{print $2}')"
  if [[ "$installflags" == *--needed* && -n "$_inst" && "$_inst" == "$pkgver-$pkgrel" ]]; then
    printf "${STY_CYAN}[$0]: %s %s already installed; skipping build (--needed).${STY_RST}\n" "$pkgname" "$_inst"
    x popd
    return 0
  fi

  x yay -S --sudoloop $installflags --asdeps "${depends[@]}"

  # Honour `replaces` ourselves. makepkg -i runs `pacman -U --noconfirm`, which
  # does NOT act on replaces/conflicts non-interactively: pacman's "Remove the
  # conflicting X? [y/N]" prompt defaults to No, so an installed predecessor
  # (the illogical-impulse-* packages this suite supersedes, which share e.g.
  # /opt/MicroTeX or the `quickshell` provides) makes the install step abort with
  # "unresolvable package conflicts". Remove any still-installed predecessor
  # first so the build's install step is a clean upgrade. -Rdd skips dependency
  # checks: the new package re-provides whatever the old one did, so a transient
  # reverse-dep (e.g. illogical-updots -> quickshell) is satisfied again the
  # moment the new package installs.
  local _old
  for _old in "${replaces[@]:-}"; do
    [[ -n "$_old" ]] || continue
    if pacman -Qq "$_old" >/dev/null 2>&1; then
      printf "${STY_CYAN}[$0]: %s supersedes installed %s; removing it first.${STY_RST}\n" "$pkgname" "$_old"
      x sudo pacman -Rdd --noconfirm "$_old"
    fi
  done

  # man makepkg:
  # -A, --ignorearch: Ignore a missing or incomplete arch field in the build script.
  # -s, --syncdeps: Install missing dependencies using pacman. When build-time or run-time dependencies are not found, pacman will try to resolve them.
  # -f, --force: build a package even if it already exists in the PKGDEST
  # -i, --install: Install or upgrade the package after a successful build using pacman(8).
  # In https://github.com/end-4/dots-hyprland/issues/823#issuecomment-3394774645 it's suggested to use `sudo pacman -U --noconfirm *.pkg.tar.zst` instead of `makepkg -i`, however it's possible that multiple *.pkg.tar.zst exist, which makes this command not reliable.
  x makepkg -Afsi --noconfirm
  x popd
}

# Install core dependencies from the meta-packages
metapkgs=(./sdata/dist-arch/immaterial-impulse-{audio,backlight,basic,fonts-themes,kde,portal,python,screencapture,toolkit,widgets})
metapkgs+=(./sdata/dist-arch/immaterial-impulse-hyprland)
metapkgs+=(./sdata/dist-arch/immaterial-impulse-microtex-git)
metapkgs+=(./sdata/dist-arch/immaterial-impulse-quickshell-git)
metapkgs+=(./sdata/dist-arch/immaterial-impulse-bibata-modern-classic-bin)

for i in "${metapkgs[@]}"; do
  metainstallflags="--needed"
  $ask && showfun install-local-pkgbuild || metainstallflags="$metainstallflags --noconfirm"
  v install-local-pkgbuild "$i" "$metainstallflags"
done

## Optional dependencies
if pacman -Qs ^plasma-browser-integration$ ;then SKIP_PLASMAINTG=true;fi
case $SKIP_PLASMAINTG in
  true) true;;
  *)
    if $ask;then
      echo -e "${STY_YELLOW}[$0]: NOTE: The size of \"plasma-browser-integration\" is ~600 KiB, but if you don't yet have KDE on your system it'll pull an extra ~600MiB of packages.${STY_RST}"
      echo -e "${STY_YELLOW}It is needed if you want playtime of media in Firefox to be shown on the music controls widget.${STY_RST}"
      echo -e "${STY_YELLOW}Install it? [y/N]${STY_RST}"
      read -p "====> " p
    else
      p=y
    fi
    case $p in
      y) x sudo pacman -S --needed --noconfirm plasma-browser-integration ;;
      *) echo "Ok, won't install"
    esac
    ;;
esac

## Optional: qs-wallpaperengine build deps (gated by INSTALL_WE, see
## sdata/subcmd-install/4.wallpaperengine.sh). Package names taken directly
## from linux-wallpaperengine's packaging/archlinux/PKGBUILD (depends +
## makedepends) in the Almamu/linux-wallpaperengine tree that
## qs-wallpaperengine's bootstrap.sh clones and patches. cmake/qt6base/
## qt6declarative etc. for the Quickshell rebuild itself are already covered
## by immaterial-impulse-quickshell-git's own PKGBUILD deps above, so they're
## not repeated here.
install_we_build_deps(){
  x sudo pacman -S --needed --noconfirm \
    lz4 ffmpeg mpv glfw glew freeglut libpulse libcups at-spi2-core nss \
    libxcomposite libxdamage nspr \
    git cmake sdl2 glm wayland-protocols xorg-xrandr \
    `# Quickshell's own build deps - the WE step recompiles Quickshell, and` \
    `# these are NOT guaranteed present (the migration's -R can drop cpptrace` \
    `# et al. as orphans of the old quickshell). cpptrace was the cmake blocker.` \
    cpptrace cli11 ninja qt6-shadertools spirv-tools vulkan-headers wayland jemalloc
}
if [[ "${INSTALL_WE:-0}" == "1" ]]; then
  showfun install_we_build_deps
  v install_we_build_deps
fi
