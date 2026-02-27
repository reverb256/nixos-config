# Fingerprint Scanner Module
# Support for fingerprint authentication
{
  pkgs,
  config,
  ...
}: {
  # Install fingerprint tools
  environment.systemPackages = with pkgs; [
    fprintd
    libfprint
  ];

  # Enable fingerprint service
  # services.fprintd = {
  #   enable = config.services.fprintd.enable or false;
  #   tod = {
  #     enable = false;  # TOD (Touchpad) detection for fingerprint
  #   };
  # };

  # PAM configuration for fingerprint auth
  # security.pam.services = {
  #   fprintd = {};
  # };

  # ============================================================================
  # FINGERPRINT AUTHENTICATION
  # ============================================================================
  #
  # To enable fingerprint authentication:
  #
  # 1. Enable the service:
  #    services.fprintd.enable = true;
  #
  # 2. Enroll your fingerprint:
  #    fprintd-enroll
  #
  # 3. Test fingerprint login:
  #    fprintd-verify
  #
  # 4. Configure PAM services:
  #    - sudo: Enable for sudo authentication
  #    - polkit: Enable for GUI authentication
  #    - greetd: Enable for display manager
  #
  # 5. For YubiKey + Fingerprint (2FA):
  #    See modules/security/yubikey.nix
  #
  # ============================================================================
}
