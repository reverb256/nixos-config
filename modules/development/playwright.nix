# Playwright - Browser automation and testing framework
# Installed globally for all users with all necessary dependencies
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Install Playwright and all browser dependencies system-wide
  environment.systemPackages = with pkgs; [
    # Playwright CLI
    playwright

    # Core browser dependencies for Chromium
    alsa-lib
    atk
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libGL
    libgbm
    libnotify
    libpulseaudio
    libudev0-shim
    libxkbcommon
    mesa
    nspr
    nss
    pango
    pipewire
    systemd
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
  ];

  # Set PLAYWRIGHT_BROWSERS_PATH globally for all users
  environment.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = "/home/j_kro/playwright-browsers";
  };

  # Ensure fonts are available for rendering
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
  ];
}
