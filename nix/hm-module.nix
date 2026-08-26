{ self }:
{ config, lib, pkgs, ... }:

# The three-tier split this module implements is settled in
# docs/proposals/nixos-flake.md ("Declarative vs mutable"):
#
#   immutable     the QML tree, scripts/, the matugen config + templates
#                 -> symlinked from the store, owned by this module outright
#   seeded once   ~/.config/immaterial-impulse/{config.json,
#                 plugin-state.json, plugins/}
#                 -> real files, written by the activation script ONLY when
#                    absent; the user's from first write onward
#   never managed every matugen OUTPUT
#                 -> plain files the running shell rewrites on every
#                    wallpaper change; this module must refuse to touch them
#
# The third tier is the trap: a matugen output managed with home.file/
# xdg.configFile becomes a store symlink, matugen either fails against the
# read-only target or replaces the symlink, and the next `home-manager
# switch` silently reverts the user's generated colours. This module never
# declares one, and warns when the surrounding home-manager configuration
# does.
let
  cfg = config.programs.immaterial-impulse;

  # dots/.config/matugen/config.toml's output_path list, as home-manager
  # attribute names. Six under ~/.config (xdg.configFile), five under
  # ~/.local/state (xdg.stateFile).
  matugenConfigOutputs = [
    "hypr/hyprland/colors.lua"
    "hypr/hyprlock/colors.conf"
    "fuzzel/fuzzel_theme.ini"
    "kitty/colors-matugen.conf"
    "gtk-3.0/gtk.css"
    "gtk-4.0/gtk.css"
  ];
  matugenStateOutputs = [
    "quickshell/user/generated/colors.json"
    "quickshell/user/generated/color.txt"
    "quickshell/user/generated/wallpaper/path.txt"
    "quickshell/user/generated/apps/cava.ini"
    "quickshell/user/generated/apps/tmux.conf"
  ];

  managedIn = fileset: paths:
    builtins.filter (p: (fileset ? ${p}) && (fileset.${p}.enable or true)) paths;

  emptyPluginState = pkgs.writeText "plugin-state.json" "{}\n";
in
{
  options.programs.immaterial-impulse = {
    enable = lib.mkEnableOption "Immaterial Impulse, a Quickshell shell for Hyprland";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.immaterial-impulse;
      defaultText = lib.literalExpression
        "immaterial-impulse.packages.\${system}.immaterial-impulse";
      description = "The shell tree linked to ~/.config/quickshell/imi.";
    };

    quickshell.package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.quickshell-wrapped;
      defaultText = lib.literalExpression
        "immaterial-impulse.packages.\${system}.quickshell-wrapped";
      description = "The quickshell build that runs the shell (`qs -c imi`).";
    };

    seedConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Seed ~/.config/immaterial-impulse/config.json from the shell's
        curated defaults on first activation. Never touches an existing
        file - it is the user's live settings, which the shell itself
        rewrites; managing it declaratively would fight the running shell
        the same way managing a matugen output would.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.quickshell.package ];

    # Tier 1: the immutable tree, straight from the store. The matugen
    # directory is config + templates only - its outputs land elsewhere.
    xdg.configFile."quickshell/imi".source = cfg.package;
    xdg.configFile."matugen".source = "${self}/dots/.config/matugen";

    # Tier 2: seeded once, only when absent, then never touched again.
    # `run` keeps this honest under `home-manager switch --dry-run`.
    home.activation.immaterialImpulseSeed =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        imiConfDir="''${XDG_CONFIG_HOME:-$HOME/.config}/immaterial-impulse"
        run mkdir -p "$imiConfDir/plugins"
        ${lib.optionalString cfg.seedConfig ''
          if [ ! -e "$imiConfDir/config.json" ]; then
            run install -m 0644 \
              "${cfg.package}/defaults/config.json" \
              "$imiConfDir/config.json"
          fi
        ''}
        if [ ! -e "$imiConfDir/plugin-state.json" ]; then
          run install -m 0644 \
            "${emptyPluginState}" \
            "$imiConfDir/plugin-state.json"
        fi
      '';

    # Tier 3: refused. This module manages none of these, and a matugen
    # output managed elsewhere in the configuration breaks silently - warn.
    warnings =
      map
        (p: ''
          programs.immaterial-impulse: xdg.configFile."${p}" is a matugen
          OUTPUT (declared in the shell's matugen config.toml). The running
          shell rewrites it on every wallpaper change; managing it makes it
          a store symlink that matugen fails against or replaces, and the
          next switch reverts the generated colours with no error. If you
          want that file declarative, you want matugen off, not this.
        '')
        (managedIn config.xdg.configFile matugenConfigOutputs)
      ++ map
        (p: ''
          programs.immaterial-impulse: xdg.stateFile."${p}" is a matugen
          OUTPUT the running shell rewrites on every wallpaper change; do
          not manage it declaratively.
        '')
        (managedIn config.xdg.stateFile matugenStateOutputs);
  };
}
