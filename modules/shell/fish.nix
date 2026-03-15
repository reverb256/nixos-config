# Fish Shell - System-Level Configuration
# This module enables fish at the system level and installs required packages.
# User-level shell configuration (aliases, functions, prompt) is managed by Home Manager
# in modules/home-manager/fish.nix to avoid conflicts and ensure DRY.
{pkgs, ...}: {
  # Enable Fish shell at system level (required for proper PATH setup)
  programs.fish = {
    enable = true;

    # Set user timezone for all fish sessions (including SSH)
    # This ensures TZ is set even when systemd user services don't inherit sessionVariables
    interactiveShellInit = ''
      # User time zone (system runs UTC, user sees local time)
      set -gx TZ America/Winnipeg
    '';
  };

  # Install required packages system-wide
  environment.systemPackages = with pkgs; [
    # Shell
    fish

    # Navigation
    zoxide

    # Fuzzy finder
    fzf

    # Podman management (when needed)
    lazydocker
    podman-compose
  ];
}
