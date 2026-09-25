{
  description = "Shared home-manager modules for TZ development environments";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/triplet";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mangopkgs = {
      url = "github:unmango/pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
  };

  outputs =
    inputs@{ flake-parts, self, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = with inputs; [
        treefmt-nix.flakeModule
      ];

      flake.homeModules = {
        tz = {
          imports = [ ./modules ];
          nixpkgs.overlays = with inputs; [
            mangopkgs.overlays.default
          ];
        };

        default = self.homeModules.tz;
      };

      perSystem =
        { pkgs, ... }:
        {
          devShells.default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              gnumake
              home-manager
              nixfmt
            ];
          };

          treefmt.programs = {
            actionlint.enable = true;
            deadnix.enable = true;
            nixfmt.enable = true;
            statix.enable = true;
            zizmor.enable = true;
          };
        };
    };
}
