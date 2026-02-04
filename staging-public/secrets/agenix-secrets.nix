{
  config,
  lib,
  pkgs,
  ...
}: let
  # Load the actual secrets configuration
  secretsConfig = import ./age-secrets.nix {inherit config lib pkgs;};
in {
  imports = [secretsConfig];

  # Agenix configuration
  age.secretsDir = "/run/agenix";
  age.secretsMountPoint = "/run/agenix.d";

  # Use age key file for decryption
  # Age private key stored in /root/.config/sops/age/keys.txt
  age.identityPaths = [
    "/root/.config/sops/age/keys.txt"
  ];
}
