{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.tz.salesforce = {
    enable = lib.mkEnableOption "Setup the TractorZoom SalesForce toolchain";
  };

  config = lib.mkIf config.tz.salesforce.enable {
    home.sessionVariables = {
      SF_DISABLE_TELEMETRY = "true";
    };

    home.packages = with pkgs; [
      cumulusci
      salesforce-cli
    ];
  };
}
