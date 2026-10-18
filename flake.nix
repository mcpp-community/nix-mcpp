{
  description = "mcpp — a modern C++ module-first build tool (prebuilt release binaries)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # The systems a release ships an asset for (package.nix).
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        mcpp = pkgs.callPackage ./package.nix { };
        default = mcpp;
      });

      # `mcpp-bin`, not `mcpp`: nixpkgs' `mcpp` is Matsui's C preprocessor, and
      # replacing it would break whatever depends on that.
      overlays.default = final: prev: {
        mcpp-bin = final.callPackage ./package.nix { };
      };

      checks = forAllSystems (pkgs: {
        mcpp = self.packages.${pkgs.stdenv.hostPlatform.system}.mcpp;
      });

      # A shell to build and test mcpp from a source checkout with the released mcpp. The
      # toolchains mcpp downloads are FHS binaries: on NixOS this needs
      # programs.nix-ld.enable (see README.md).
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            self.packages.${pkgs.stdenv.hostPlatform.system}.mcpp
            pkgs.git
            pkgs.jq
            pkgs.python3
            pkgs.gh
            pkgs.shellcheck
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
