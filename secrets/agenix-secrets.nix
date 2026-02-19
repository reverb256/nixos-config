{
  config,
  lib,
  pkgs,
  ...
}: {
  # Import the secrets configuration
  imports = [./age-secrets.nix];

  # Agenix configuration
  age.secretsDir = "/run/agenix";
  age.secretsMountPoint = "/run/agenix.d";

  # Use age key file for decryption
  # Age private key stored in j_kro's home directory
  age.identityPaths = [
    "/home/j_kro/.config/age/keys.txt"
  ];

  # HuggingFace token (manually encrypted with age)
  # NOTE: Temporarily disabled - recreate with: echo "TOKEN" | age -a -R ~/.config/age/keys.txt > hf-token.age
  # age.secrets.hf-token = {
  #   file = ./hf-token.age;
  #   owner = "j_kro";
  #   group = "users";
  #   mode = "400";
  # };
}
