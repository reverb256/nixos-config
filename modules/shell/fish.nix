# Fish Shell - System-Level Configuration
# This module enables fish at the system level and installs required packages.
# User-level shell configuration (aliases, functions, prompt) is managed by Home Manager
# in modules/home-manager/fish.nix to avoid conflicts and ensure DRY.
{pkgs, ...}: {
  # Enable Fish shell at system level (required for proper PATH setup)
  programs.fish.enable = true;

  # Install required packages system-wide
  environment.systemPackages = with pkgs; [
    # Shell
    fish
    fishPlugins.foreign-env
    fishPlugins.fzf-fish

    # Navigation
    zoxide

    # Fuzzy finder
    fzf

    # Podman management (when needed)
    lazydocker
    podman-compose
  ];
}
