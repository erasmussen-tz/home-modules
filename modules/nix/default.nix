{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.tz.nix = {
    enable = lib.mkEnableOption "Setup the TractorZoom Nix toolchain";
  };

  config = lib.mkIf config.tz.nix.enable {
    home.packages = with pkgs; [
      nix
      nixfmt
    ];
  };
}
