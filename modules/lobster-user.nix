# Lobster user configuration for OpenClaw agent shell access
{ config, pkgs, ... }:

{
  # Create lobster user for OpenClaw agent shell execution
  users.users.lobster = {
    isNormalUser = true;
    home = "/home/lobster";
    description = "OpenClaw Agent Shell User";
    extraGroups = [ "wheel" "video" "audio" "networkmanager" ];
    shell = pkgs.bash;
    # No password - use sudo or key-based auth only
    hashedPassword = "!";
  };

  # Allow j_kro (OpenClaw gateway user) to run commands as lobster without password
  security.sudo.extraRules = [
    {
      users = [ "j_kro" ];
      commands = [
        { command = "/run/current-system/sw/bin/bash"; options = [ "NOPASSWD" "SETENV" ]; }
        { command = "/run/current-system/sw/bin/sh"; options = [ "NOPASSWD" "SETENV" ]; }
        { command = "/run/current-system/sw/bin/nix"; options = [ "NOPASSWD" "SETENV" ]; }
        { command = "/run/current-system/sw/bin/nix-shell"; options = [ "NOPASSWD" "SETENV" ]; }
        { command = "ALL"; options = [ "NOPASSWD" "SETENV" ]; }
      ];
    }
    {
      users = [ "lobster" ];
      commands = [
        { command = "ALL"; options = [ "NOPASSWD" "SETENV" ]; }
      ];
    }
  ];

  # Ensure lobster has proper environment for Nix
  environment.sessionVariables = {
    LOBSTER_HOME = "/home/lobster";
  };

  # Create necessary directories
  systemd.tmpfiles.rules = [
    "d /home/lobster/.config 0755 lobster lobster -"
    "d /home/lobster/.openclaw 0755 lobster lobster -"
    "d /home/lobster/workspace 0755 lobster lobster -"
  ];

  # Set up proper shell environment for lobster
  home-manager.users.lobster = { pkgs, ... }: {
    home.stateVersion = "24.05";
    programs.bash = {
      enable = true;
      initExtra = ''
        # Nix environment
        if [ -e /run/current-system/sw/bin/nix ]; then
          export PATH="/run/current-system/sw/bin:$PATH"
          export NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
        fi
        # OpenClaw agent marker
        echo "[OpenClaw Agent Shell - lobster@$(hostname)]"
      '';
    };
  };
}
