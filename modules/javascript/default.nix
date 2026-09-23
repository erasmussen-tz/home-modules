# The JavaScript toolchain every TractorZoom web and service repo expects.
#
# Every module in this repo has the same two halves: `options` declares what
# can be set, `config` is what happens when it is. README.md's "Working on the
# modules" section explains the handful of Nix spellings used below.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tz.javascript;

  yaml = pkgs.formats.yaml { };

  # The literal text `${NPM_PRIVATE_READ}`, for npm and Yarn to expand when
  # they run. Built by joining three pieces because writing the `${` directly
  # would make Nix expand it instead, while the file is still being generated.
  envReference = name: "$" + "{" + name + "}";

  token = envReference cfg.registry.tokenVariable;

  # npm identifies a registry's credentials by its URL with the scheme cut
  # off, so `https://registry.npmjs.org` is keyed as `//registry.npmjs.org/`.
  registryWithoutScheme = lib.removePrefix "https:" cfg.registry.url;

  npmrc = ''
    registry=${cfg.registry.url}/
    ${registryWithoutScheme}/:_authToken=${token}
    save-exact=true
  '';

  # Yarn reads ~/.yarnrc.yml before a project's own file and lets the project
  # override any key, so these are starting points rather than rules.
  yarnrc = {
    npmRegistryServer = cfg.registry.url;
    npmAlwaysAuth = true;
    npmAuthToken = token;
  }
  # `//` merges two sets together, and `optionalAttrs` returns an empty set
  # when its condition is false, so each block below adds its key only when
  # there is something to say.
  // lib.optionalAttrs (cfg.registry.minimalAgeGate != null) {
    npmMinimalAgeGate = cfg.registry.minimalAgeGate;
  }
  // lib.optionalAttrs (cfg.registry.preapprovedPackages != [ ]) {
    npmPreapprovedPackages = cfg.registry.preapprovedPackages;
  };

  # Set when the token comes from sops, which is what makes this module
  # declare the secret and export the variable.
  fromSops = cfg.registry.tokenSopsFile != null;

  # Where sops writes the decrypted token. Only ever read when `fromSops`, so
  # naming it here is safe even though the secret may not be declared.
  tokenPath = config.sops.secrets."npm-private-read".path;
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
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.nodePackages.typescript-language-server ]";
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
        type = lib.types.nullOr lib.types.path;
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
          Registry serving the private `@tractorzoom` scope. Must start with
          `https://` and carry no trailing slash; the npm auth key and the
          `registry=` line derive theirs.
        '';
      };

      minimalAgeGate = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
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
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "@tractorzoom/types" ];
        description = ''
          Packages exempt from `minimalAgeGate`. Yarn matches these literally,
          so a scope cannot be named as a whole.
        '';
      };
    };
  };

  # Everything below applies only when the module is turned on. That is what
  # `lib.mkIf` does, and it is why an unused module costs nothing.
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "https://" cfg.registry.url;
        message = ''
          tz.javascript.registry.url is "${cfg.registry.url}", which does not
          start with https://. The npm auth key is derived by cutting the
          scheme off that URL, and an npm token is a bearer credential that
          must not travel in the clear.
        '';
      }
    ];

    warnings = lib.optional (!fromSops) ''
      tz.javascript.registry.tokenSopsFile is not set, so
      ${cfg.registry.tokenVariable} is never exported and installing a private
      @tractorzoom package will fail to authenticate. Point it at a
      sops-encrypted file holding the token, or export
      ${cfg.registry.tokenVariable} yourself.
    '';

    home.packages = [
      pkgs.biome
      pkgs.commitlint
      pkgs.fnm
      pkgs.lefthook
      pkgs.yarn-berry
    ]
    ++ cfg.extraPackages;

    home.file.".npmrc".text = npmrc;
    home.file.".yarnrc.yml".source = yaml.generate "yarnrc.yml" yarnrc;

    sops.secrets = lib.optionalAttrs fromSops {
      "npm-private-read" = {
        sopsFile = cfg.registry.tokenSopsFile;
        key = cfg.registry.tokenSopsKey;
      };
    };

    # Guarded rather than a plain `home.sessionVariables` entry: before the
    # first activation decrypts the secret the path does not exist, and an
    # unguarded `cat` would print an error on every new shell.
    home.sessionVariablesExtra = lib.optionalString fromSops ''
      if [ -r "${tokenPath}" ]; then
        export ${cfg.registry.tokenVariable}="$(cat "${tokenPath}")"
      fi
    '';
  };
}
