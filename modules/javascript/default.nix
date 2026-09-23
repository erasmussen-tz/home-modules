{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tz.javascript;

  inherit (cfg.registry) tokenVariable;

  # npm keys auth by the registry URL with the scheme stripped and a trailing
  # slash, so `https://registry.npmjs.org` becomes `//registry.npmjs.org/`.
  authKey = "${
    lib.removeSuffix "/" (
      builtins.replaceStrings
        [
          "https:"
          "http:"
        ]
        [
          ""
          ""
        ]
        cfg.registry.url
    )
  }/";

  npmrc = ''
    registry=${cfg.registry.url}/
    ${authKey}:_authToken=''${${tokenVariable}}
    save-exact=true
  '';

  # Yarn reads ~/.yarnrc.yml first and lets a project's file override any key,
  # so this is a floor rather than a mandate. Rendered by hand rather than
  # through pkgs.formats.yaml because the token reference has to survive
  # unquoted: Yarn only interpolates ${VAR} outside quotes.
  yarnrc = ''
    npmRegistryServer: "${cfg.registry.url}"
    npmAlwaysAuth: true
    npmAuthToken: ''${${tokenVariable}}
  ''
  + lib.optionalString (cfg.registry.minimalAgeGate != null) ''
    npmMinimalAgeGate: ${toString cfg.registry.minimalAgeGate}
  ''
  + lib.optionalString (cfg.registry.preapprovedPackages != [ ]) (
    # Quoted strings rather than an indented block: Nix strips a single-line
    # `''` literal's whole leading margin, so the entries would come out flush
    # against column zero.
    "npmPreapprovedPackages:\n"
    + lib.concatMapStrings (name: "  - \"${name}\"\n") cfg.registry.preapprovedPackages
  );
in
{
  options.tz.javascript = {
    enable = lib.mkEnableOption "TractorZoom JavaScript toolchain";

    packages = lib.mkOption {
      type = with lib.types; listOf package;
      default = with pkgs; [
        biome
        commitlint
        fnm
        lefthook
        yarn-berry
      ];
      defaultText = lib.literalExpression ''
        with pkgs; [ biome commitlint fnm lefthook yarn-berry ]
      '';
      description = ''
        Tooling every TractorZoom JavaScript checkout expects on PATH. Node
        itself is absent on purpose: each repo pins a version in `.nvmrc` and
        `fnm` supplies it, so a global `nodejs` would only shadow the pin.
        `fnm`'s shell hook is left to whichever module owns the shell.
      '';
    };

    registry = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "https://registry.npmjs.org";
        description = ''
          Registry serving the private `@tractorzoom` scope. No trailing
          slash; the npm auth key and the `registry=` line derive theirs.
        '';
      };

      tokenVariable = lib.mkOption {
        type = lib.types.str;
        default = "NPM_PRIVATE_READ";
        description = ''
          Environment variable both rc files reference for the read token.
          Named rather than inlined so the token never reaches the world
          readable nix store, and matching the variable the checked-in
          per-repo `.npmrc` and `.yarnrc.yml` files already interpolate.
        '';
      };

      tokenFile = lib.mkOption {
        type = with lib.types; nullOr path;
        default = null;
        example = lib.literalExpression ''config.sops.secrets."npm-private-read".path'';
        description = ''
          Runtime path of a file holding the token. Read at shell startup to
          export `tokenVariable`, which is what makes the per-repo rc files
          resolve. A path rather than a sops secret name because the value is
          only ever needed at runtime, which keeps this module usable without
          sops-nix. Null leaves the export to the caller.
        '';
      };

      minimalAgeGate = lib.mkOption {
        type = with lib.types; nullOr int;
        default = 11520;
        description = ''
          Minutes a version must have been published before Yarn will install
          it, as a supply chain delay. 11520 is eight days. Set at home level
          so a fresh checkout is covered before anyone edits its rc file;
          repos publishing internally on a shorter cycle list the affected
          packages in their own `npmPreapprovedPackages`. Null omits the key.
        '';
      };

      preapprovedPackages = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        example = [ "@tractorzoom/types" ];
        description = ''
          Packages exempt from `minimalAgeGate`. Yarn matches these literally,
          so a scope cannot be named as a whole.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = cfg.packages;

    home.file.".npmrc".text = npmrc;
    home.file.".yarnrc.yml".text = yarnrc;

    # Guarded rather than a `home.sessionVariables` entry: an unreadable or
    # not yet decrypted secret would otherwise print an error on every shell.
    home.sessionVariablesExtra = lib.mkIf (cfg.registry.tokenFile != null) ''
      if [ -r "${cfg.registry.tokenFile}" ]; then
        export ${tokenVariable}="$(cat "${cfg.registry.tokenFile}")"
      fi
    '';
  };
}
