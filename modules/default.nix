{ lib, ... }:
{
  imports = [
    ./aws
    ./javascript
    ./nix
    ./salesforce
    ./secrets
  ];

  options.tz.enable = lib.mkEnableOption ''
    Configure every TractorZoom toolchain module
  '';
}
