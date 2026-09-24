{ lib, ... }:
{
  imports = [
    ./aws
    ./javascript
    ./nix
    ./salesforce
  ];

  options.tz.enable = lib.mkEnableOption ''
    Configure every TractorZoom toolchain module
  '';
}
