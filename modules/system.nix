# System Module
# Extracted from configuration.nix - System-level configurations
{pkgs, ...}: {
  # ============================================================================
  # TIMEZONE AND LOCALE
  # ============================================================================

  time.timeZone = "America/Winnipeg";
  i18n.defaultLocale = "en_CA.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_CA.UTF-8";
    LC_IDENTIFICATION = "en_CA.UTF-8";
    LC_MEASUREMENT = "en_CA.UTF-8";
    LC_MONETARY = "en_CA.UTF-8";
    LC_NAME = "en_CA.UTF-8";
    LC_NUMERIC = "en_CA.UTF-8";
    LC_PAPER = "en_CA.UTF-8";
    LC_TELEPHONE = "en_CA.UTF-8";
    LC_TIME = "en_CA.UTF-8";
  };

  # ============================================================================
  # FONTS
  # ============================================================================
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
    jetbrains-mono
  ];

  # ============================================================================
  # SYSTEM OPTIMIZATIONS
  # ============================================================================

  # Note: powerManagement.cpuFreqGovernor is set in configuration.nix
  # Note: zramSwap is configured in configuration.nix
  # Note: OOM handling uses services.earlyoom from configuration.nix
}
