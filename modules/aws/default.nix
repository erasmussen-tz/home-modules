{
  pkgs,
  lib,
  config,
}:
{
  options.tz.aws = {
    enable = lib.mkEnableOption "Setup the TractorZoom AWS toolchain";
  };

  config = lib.mkIf config.tz.aws.enable {
    home.packages = with pkgs; [
      awscli2
      aws-cdk-cli
      aws-sam-cli
    ];
  };
}
