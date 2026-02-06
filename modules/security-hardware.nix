# ============================================================================
# YUBIKEY AND SECURITY HARDWARE CONFIGURATION
# ============================================================================
{pkgs, ...}: {
  # YubiKey Manager for device configuration
  programs.yubikey-manager.enable = true;

  # Bitwarden CLI for password management
  programs.bitwarden.enable = true;

  # Enable SSH agent for key management
  programs.ssh.startAgent = true;

  # GPG agent for YubiKey PGP keys (if used)
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry;
  };

  # Udev rules for YubiKey detection
  services.udev.extraRules = ''
    # YubiKey USB devices
    SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="*", TAG+="uaccess"
  '';
}
