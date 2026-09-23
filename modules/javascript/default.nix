{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tz.javascript;

  inherit (cfg.registry) tokenVariable;

  # The one sops secret this module declares. Fixed rather than exposed as an
  # option: nothing outside this file refers to it.
  secret = "npm-private-read";

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
    # `''` literal's whole leading margin, so the entries would come out
    # flush against column zero.
    "npmPreapprovedPackages:\n"
    + lib.concatMapStrings (name: "  - \"${name}\"\n") cfg.registry.preapprovedPackages
  );
in
{
  options.tz.javascript = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.tz.enable;
      defaultText = lib.literalExpression "config.tz.enable";
      description = ''
        Set up the TractorZoom JavaScript toolchain: biome, commitlint, fnm,
        lefthook and yarn on PATH, and `~/.npmrc` and `~/.yarnrc.yml` written
        so the private `@tractorzoom` packages install.
      '';
    };

    extraPackages = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
      example = lib.literalExpression "with pkgs; [ nodePackages.typescript-language-server ]";
      description = ''
        Extra tools to put on PATH alongside the toolchain above. Added to the
        defaults rather than replacing them, so listing one tool here cannot
        cost you the linter. Dropping a default is a change to this repo.

        Node itself is deliberately not installed: every repo pins a version
        in its `.nvmrc` and `fnm` supplies that, so a system-wide `nodejs`
        would only shadow the pin.
      '';
    };

    registry = {
      tokenSopsFile = lib.mkOption {
        type = with lib.types; nullOr path;
        default = null;
        example = lib.literalExpression "./secrets/npm.yaml";
        description = ''
          A sops-encrypted YAML file holding the npm read token. This module
          declares the sops secret and points both rc files at it, so nothing
          else needs wiring up. Edit the file with `sops <path>`; the key
          inside it is `tokenSopsKey`.

          The token is read at shell startup from the decrypted copy, so it
          never lands in the world-readable nix store. Leaving this null
          leaves the token to be exported some other way.
        '';
      };

      tokenSopsKey = lib.mkOption {
        type = lib.types.str;
        default = "npm_private_read";
        description = "Key inside `tokenSopsFile` holding the token.";
      };

      tokenVariable = lib.mkOption {
        type = lib.types.str;
        default = "NPM_PRIVATE_READ";
        description = ''
          Environment variable both rc files read the token from. Matches the
          variable the checked-in per-repo `.npmrc` and `.yarnrc.yml` files
          already interpolate, so those keep working unchanged.
        '';
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "https://registry.npmjs.org";
        description = ''
          Registry serving the private `@tractorzoom` scope. No trailing
          slash; the npm auth key and the `registry=` line derive theirs.
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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages =
          (with pkgs; [
            biome
            commitlint
            fnm
            lefthook
            yarn-berry
          ])
          ++ cfg.extraPackages;

        home.file.".npmrc".text = npmrc;
        home.file.".yarnrc.yml".text = yarnrc;

        warnings = lib.optional (cfg.registry.tokenSopsFile == null) ''
          tz.javascript.registry.tokenSopsFile is not set, so ${tokenVariable}
          is never exported and installing a private @tractorzoom package will
          fail to authenticate. Point it at a sops-encrypted file holding the
          token, or export ${tokenVariable} yourself.
        '';
      }

      (lib.mkIf (cfg.registry.tokenSopsFile != null) {
        sops.secrets.${secret} = {
          sopsFile = cfg.registry.tokenSopsFile;
          key = cfg.registry.tokenSopsKey;
        };

        # Guarded rather than a `home.sessionVariables` entry: before the first
        # activation decrypts the secret the path does not exist, and an
        # unguarded `cat` would print an error on every new shell.
        home.sessionVariablesExtra = ''
          if [ -r "${config.sops.secrets.${secret}.path}" ]; then
            export ${tokenVariable}="$(cat "${config.sops.secrets.${secret}.path}")"
          fi
        '';
      })
    ]
  );
}
