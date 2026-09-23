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
    every TractorZoom toolchain module at once. Each `tz.<name>.enable`
    defaults to this, so a single `tz.enable = true` is enough to set a
    machine up, and any one piece can still be turned back off by setting
    its own `enable` to false
  '';
}
