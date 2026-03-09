# Home Manager User Configuration
# Shared Home Manager configuration for j_kro across all cluster nodes
{
  inputs,
  pkgs,
  ...
}: {
  home-manager = {
    backupFileExtension = "bak";

    users.j_kro = {pkgs, ...}: {
      imports = [
        ../../modules/home-manager/fish.nix
        ../../modules/home-manager/starship.nix
      ];

      home.stateVersion = "26.05";

      # systemd user environment for secrets (available in all shells)
      systemd.user.sessionVariables = {
        HF_TOKEN = "/run/agenix/huggingface-token";
      };
    };
  };
}
