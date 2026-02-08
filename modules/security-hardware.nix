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

  # SSH agent is managed by distributed-builds.nix (coordinated across all nodes)
  # programs.ssh.startAgent is set there to avoid conflicts

  # GPG agent for YubiKey PGP keys (if used)
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false;
    pinentryPackage = pkgs.pinentry-curses;
  };

  # Udev rules for YubiKey detection
  services.udev.extraRules = ''
    # YubiKey USB devices
    SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="*", TAG+="uaccess"
  '';
}
