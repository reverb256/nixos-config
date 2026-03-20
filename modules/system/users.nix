# User Accounts Module
{
  pkgs,
  lib,
  ...
}: {
  users.users.j_kro = {
    isNormalUser = true;
    description = "Jeremy Kroeker";
    shell = pkgs.fish;
    extraGroups = ["networkmanager" "wheel" "render" "video" "libinput" "ai-inference" "plugdev" "openrazer" "gamemode"];
    packages = with pkgs; [
      kdePackages.kate
      kdePackages.yakuake # Drop-down terminal emulator
      gh # GitHub CLI
      nodejs # Node.js runtime
    ];
  };

  # User timezone - Local time for user sessions (system time remains UTC)
  # This ensures users see their local timezone while system logs use UTC
  # Use mkOptionDefault so it can be overridden if needed
  environment.sessionVariables = lib.mkOptionDefault {
    TZ = "America/Winnipeg"; # Central Time (CDT/CST)
  };

  # PAM environment - ensures TZ is set for all sessions including SSH
  security.pam.services.login.setEnvironment = true;

  # Also write TZ to /etc/environment for systemd user services
  environment.etc."environment".text = ''
    TZ=America/Winnipeg
  '';

  # Allow passwordless sudo for j_kro
  security.sudo = {
    enable = true;
    extraConfig = "j_kro ALL=(ALL) NOPASSWD: ALL";
  };

  # Create groups for device and service access
  users.groups.plugdev = {};
  users.groups.gamemode = {};
}
