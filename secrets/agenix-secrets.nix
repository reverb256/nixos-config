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
}
