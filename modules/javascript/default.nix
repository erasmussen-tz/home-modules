{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.tz.javascript = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.tz.enable;
      defaultText = lib.literalExpression "config.tz.enable";
      description = ''
        Set up the TractorZoom JavaScript toolchain
      '';
    };
  };

  config = lib.mkIf config.tz.javascript {
    home.packages = with pkgs; [
      biome
      commitlint
      fnm # replaces nvm
      lefthook
      yarn-berry
    ];
  };
}
