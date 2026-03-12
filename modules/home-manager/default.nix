# Home Manager Configuration - Main Entry Point
# Centralized user configuration for j_kro across all cluster nodes
{
  inputs,
  ...
}: {
  home-manager = {
    backupFileExtension = "bak";

    # Pass inputs to user configs so flake inputs are accessible
    extraSpecialArgs = {inherit inputs;};

    users.j_kro = {inputs, ...}: {
      imports = [
        inputs.zen-browser.homeModules.twilight
        inputs.nixcord.homeModules.nixcord
        ./fish.nix
        ./starship.nix
        ./wayland-tools.nix
        ./zen-browser.nix
        ./nixcord-config.nix
      ];

      home.stateVersion = "26.05";

      # systemd user environment for secrets (available in all shells)
      systemd.user.sessionVariables = {
        HF_TOKEN = "/run/agenix/huggingface-token";
      };
    };
  };
}
