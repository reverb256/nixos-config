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

  # Use SSH host keys for age decryption (ssh-to-age)
  # Agenix will automatically convert SSH keys to age keys
  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
    "/etc/ssh/ssh_host_rsa_key"
  ];
}
