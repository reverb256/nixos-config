# User Accounts Module
{pkgs, ...}: {
  users.users.j_kro = {
    isNormalUser = true;
    description = "Jeremy Kroeker";
    shell = pkgs.fish;
    extraGroups = ["networkmanager" "wheel" "render" "video" "libinput" "ai-inference" "plugdev"];
    packages = with pkgs; [
      kdePackages.kate
      kdePackages.yakuake # Drop-down terminal emulator
      gh # GitHub CLI
      nodejs # Node.js runtime
    ];
  };

  # Allow passwordless sudo for j_kro
  security.sudo = {
    enable = true;
    extraConfig = "j_kro ALL=(ALL) NOPASSWD: ALL";
  };

  # Create plugdev group for device access (Arduino, FTDI, USB devices)
  users.groups.plugdev = {};
}
