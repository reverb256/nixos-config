# Lobster user configuration for  agent shell access
{ config, pkgs, ... }:

{
  # Create lobster user for  agent shell execution
  users.users.lobster = {
    isNormalUser = true;
    home = "/home/lobster";
    description = " Agent Shell User";
    extraGroups = [ "wheel" "video" "audio" "networkmanager" ];
    shell = pkgs.bash;
    # No password - use sudo or key-based auth only
    hashedPassword = "!";
  };

  # Note: No sudo access granted -  runs native commands as current user
  # Shell access is provided through 's native/exec tools, not sudo
  environment.sessionVariables = {
    LOBSTER_HOME = "/home/lobster";
  };

  # Create necessary directories
  systemd.tmpfiles.rules = [
    "d /home/lobster/.config 0755 lobster lobster -"
    "d /home/lobster/workspace 0755 lobster lobster -"
  ];

}
