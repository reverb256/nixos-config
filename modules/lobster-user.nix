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

  # Allow lobster to run commands without password for OpenClaw agent
  security.sudo.extraRules = [
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
}
