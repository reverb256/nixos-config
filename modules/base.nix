# Base Module - Common system settings for ALL hosts
# Timezone, locale, fonts, system optimizations
{pkgs, ...}: {
  # ============================================================================
  # TIMEZONE AND LOCALE (Shared across all hosts)
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
  # FONTS (Shared across all hosts)
  # ============================================================================

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
    jetbrains-mono
  ];

  # ============================================================================
  # SYSTEM OPTIMIZATIONS (Shared across all hosts)
  # ============================================================================

  # CPU governor for performance
  powerManagement.cpuFreqGovernor = "performance";

  # Memory management with zram
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  # OOM daemon for memory pressure management
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableSystemSlice = true;
  };

  # Enable home-manager for user configuration (SSH, starship, etc.)
  programs.home-manager.enable = true;
}
