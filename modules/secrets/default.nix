{ config, lib, ... }:
{
  # Where sops looks for the age private key that decrypts every secret these
  # modules declare. Set here so that enabling a module which needs a secret
  # is enough on its own: without it, sops-nix aborts with "No key source
  # configured for sops", which names no file and no fix.
  #
  # mkDefault, so a consumer already managing sops keeps its own setting,
  # whether that is another path or gnupg instead of age.
  sops.age.keyFile = lib.mkDefault "${config.xdg.configHome}/sops/age/keys.txt";
}
