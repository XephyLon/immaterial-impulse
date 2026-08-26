{ lib, stdenvNoCC, version }:

# The shell tree - the contents of dots/.config/quickshell/imi - as a store
# path. This is the whole tree the installer would rsync to
# ~/.config/quickshell/imi, tests and probes included, because the matugen
# config and several services resolve scripts inside it by that layout.
# Nothing in the shell writes into this directory (settled in
# docs/proposals/nixos-flake.md, "Declarative vs mutable"): every
# writeAdapter/setText consumer targets ~/.config/immaterial-impulse or
# XDG state, so a read-only store path needs no part of the shell relaxed.
stdenvNoCC.mkDerivation {
  pname = "immaterial-impulse";
  inherit version;

  src = lib.cleanSource ../dots/.config/quickshell/imi;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R ./. "$out"/
    runHook postInstall
  '';

  meta = {
    description = "Immaterial Impulse - a Quickshell shell configuration for Hyprland";
    homepage = "https://github.com/XephyLon/immaterial-impulse";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
