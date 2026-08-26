{
  description = "Immaterial Impulse - a Quickshell shell configuration for Hyprland";

  inputs = {
    # Kept on the same channel the nested sdata/dist-nix flake pins, so the
    # two resolve the same package set for as long as both exist.
    nixpkgs.url = "nixpkgs/nixos-25.11";

    # Deliberately no commit in this URL: the pin lives in flake.lock, where
    # `nix flake update quickshell` can move it and the diff shows what moved.
    # The nested sdata/dist-nix flake used to hardcode a commit here, which is
    # a pin nothing updates and nothing explains.
    quickshell = {
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, quickshell, ... }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: lib.genAttrs systems f;
      version = lib.removeSuffix "\n" (builtins.readFile ./VERSION);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        rec {
          # The shell tree (dots/.config/quickshell/imi) as a store path.
          immaterial-impulse = pkgs.callPackage ./nix/package.nix {
            inherit version;
          };

          # The Qt-bundled quickshell wrapper the nested home-manager flake
          # already carries - reused, not rewritten (see that file's header).
          quickshell-wrapped = import ./sdata/dist-nix/home-manager/quickshell.nix {
            inherit pkgs;
            qsPackage = quickshell.packages.${system}.default;
          };

          default = immaterial-impulse;
        });

      homeManagerModules = rec {
        immaterial-impulse = import ./nix/hm-module.nix { inherit self; };
        default = immaterial-impulse;
      };

      # No nixosModules yet, deliberately: the home-manager module covers the
      # shell itself, and the system-level pieces the installer does (SDDM
      # theme, plymouth, polkit rules, services) are future work - see
      # docs/proposals/nixos-flake.md, "Open questions".

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = import ./nix/dev-shell.nix {
            inherit pkgs;
            quickshellWrapped = self.packages.${system}.quickshell-wrapped;
          };
        });

      checks = forAllSystems (system: {
        package = self.packages.${system}.immaterial-impulse;
      });
    };
}
