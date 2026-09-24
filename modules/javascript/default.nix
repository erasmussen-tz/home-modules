{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.tz.javascript = {
    enable = lib.mkEnableOption "Setup the TractorZoom JavaScript toolchain";
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
