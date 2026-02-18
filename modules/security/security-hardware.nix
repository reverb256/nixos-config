# ============================================================================
# YUBIKEY AND SECURITY HARDWARE CONFIGURATION
# Supports: YubiKey, Passkeys, FIDO2, U2F
# ============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.security.hardware;
in {
  options.security.hardware = {
    yubikey = {
      enable = mkEnableOption "YubiKey support with U2F and FIDO2";
      enableSSHSupport = mkOption {
        type = types.bool;
        default = true;
        description = "Enable YubiKey as SSH authentication provider";
      };
    };

    passkey = {
      enable = mkEnableOption "WebAuthn/FIDO2 passkey support for browsers";
    };
  };

  config = mkMerge [
    # YubiKey configuration
    (mkIf cfg.yubikey.enable {
      # YubiKey Manager CLI and GUI
      programs.yubikey-manager = {
        enable = true;
      };

      # YubiKey Personalization Tool for OTP configuration
      environment.systemPackages = with pkgs; [
        yubikey-personalization
        yubikey-personalization-gui
        yubioath-flutter # Authenticator app
      ];

      # Udev rules for YubiKey detection
      services.udev.extraRules = ''
        # YubiKey USB devices - allow user access
        SUBSYSTEM=="usb", ATTR{idVendor}=="1050", ATTR{idProduct}=="*", TAG+="uaccess"

        # YubiKey HID interface
        KERNEL=="hidraw*", ATTRS{idVendor}=="1050", MODE="0660", GROUP="plugdev"
      '';

      # GPG agent for YubiKey PGP keys
      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = cfg.yubikey.enableSSHSupport;
        pinentryPackage = pkgs.pinentry-qt;
      };

      # PC/SC smart card daemon for YubiKey
      services.pcscd.enable = true;
    })

    # Passkey/FIDO2 configuration
    (mkIf cfg.passkey.enable {
      # Hardware security key support for browsers
      hardware.u2f.enable = true;

      # Udev rules for FIDO2/WebAuthn devices
      services.udev.extraRules = ''
        # FIDO2/WebAuthn authenticators
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1050", MODE="0660", GROUP="plugdev"
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="20a0", MODE="0660", GROUP="plugdev"
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="096e", MODE="0660", GROUP="plugdev"
      '';
    })

    # Common security tools (always enabled)
    {
      environment.systemPackages = with pkgs; [
        rbw # Rust Bitwarden CLI (headless password manager)
        bitwarden-cli # Official Bitwarden CLI
        age # Age encryption tool
        rage # Rust implementation of age
      ];
    }
  ];
}
