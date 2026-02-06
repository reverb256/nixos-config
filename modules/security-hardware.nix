# ============================================================================
# YUBIKEY AND SECURITY HARDWARE CONFIGURATION
# ============================================================================
{pkgs, ...}: {
  # YubiKey Manager for device configuration
  programs.yubikey-manager.enable = true;

  # RBW - Rust Bitwarden CLI (headless password manager)
  environment.systemPackages = with pkgs; [
    rbw
  ];

  # Enable SSH agent for key management
  programs.ssh.startAgent = true;

  # GPG agent for YubiKey PGP keys (if used)
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false;
    pinentryPackage = pkgs.pinentry;
  };

  # Udev rules for YubiKey detection
  services.udev.extraRules = ''
    # YubiKey USB devices
    SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="*", TAG+="uaccess"
  '';
}
