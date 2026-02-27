{
  config,
  lib,
  pkgs,
  ...
}: {
  # Agenix configuration
  age.secretsDir = "/run/agenix";
  age.secretsMountPoint = "/run/agenix.d";

  # Use rage instead of age for native SSH key support
  age.ageBin = "${pkgs.rage}/bin/rage";

  # Use SSH host keys for decryption (works on all nodes)
  # Each node can decrypt secrets encrypted with its host SSH key
  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  # Import the secrets configuration
  # All secrets are encrypted with age public keys from all nodes
  imports = [./age-secrets.nix];
}
