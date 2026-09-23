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

    # Only used to evaluate `checks.homeConfiguration`. A consumer brings its
    # own, and nothing under `modules/` refers to this.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pulled in so a consumer gets secret decryption by importing one module
    # rather than wiring sops-nix up themselves. Its home-manager module is
    # inert while `sops.secrets` is empty, so importing it costs nothing.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = with inputs; [
        treefmt-nix.flakeModule
      ];

      # A consumer imports `homeModules.tz` and nothing else. Depending on
      # sops-nix here rather than in `modules/` keeps flake inputs out of the
      # modules themselves, which is what lets them be evaluated directly.
      #
      # A consumer that also imports sops-nix on its own must add
      # `inputs.home-modules.inputs.sops-nix.follows = "sops-nix"`, or the
      # module system sees two copies declaring `options.sops` and rejects the
      # duplicate. README.md spells this out.
      flake.homeModules =
        let
          tz = {
            imports = [
              inputs.sops-nix.homeModules.sops
              ./modules
            ];
          };
        in
        {
          inherit tz;
          default = tz;
        };

      perSystem =
        { pkgs, ... }:
        {
          # `nix flake check` never evaluates `homeModules`, so a module that
          # fails to evaluate would otherwise reach a consumer unnoticed.
          # Building one configuration with everything turned on is what
          # catches it.
          checks.homeConfiguration =
            (inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                inputs.self.homeModules.tz
                {
                  home.username = "check";
                  home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/check" else "/home/check";
                  home.stateVersion = "26.05";

                  tz.enable = true;

                  # Never decrypted, only evaluated, which is what exercises
                  # the branch that declares the sops secret.
                  tz.javascript.registry.tokenSopsFile = ./checks/npm.yaml;
                  tz.javascript.registry.preapprovedPackages = [ "@tractorzoom/types" ];
                }
              ];
            }).activationPackage;

          devShells.default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              gnumake
              nixfmt
            ];
          };

          treefmt.programs = {
            nixfmt.enable = true;
          };
        };
    };
}
