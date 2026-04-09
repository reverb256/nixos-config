# Web Testing Module
# Provides system libraries for Playwright, Puppeteer, and browser automation
{
  pkgs,
  lib,
  config,
  ...
}: {
  options.services.web-testing = {
    enable = lib.mkEnableOption "Web testing libraries for Playwright/Puppeteer";
  };

  config = lib.mkIf config.services.web-testing.enable {
    # ============================================================================
    # ENVIRONMENT CONFIGURATION
    # ============================================================================
    environment = {
      # Playwright browsers are downloaded to ~/playwright-browsers
      # Set this globally so all projects can find the browsers
      sessionVariables.PLAYWRIGHT_BROWSERS_PATH = "/home/j_kro/playwright-browsers";

      # System libraries for Chromium/Playwright
      # Playwright bundles its own Chromium binary, which needs these libraries
      systemPackages = with pkgs;
        [
          # Playwright CLI
          playwright
        ]
        ++ (with pkgs; [
          # GTK/GNOME libraries required by Chromium
          glib
          glibc
          gtk3
          gtk4
          gdk-pixbuf
          pango
          cairo
          atk
          cups
          libdrm
          libxkbcommon
          libxrandr
          libxcb
          libxcomposite
          libxcursor
          libxdamage
          libxext
          libxfixes
          libxi
          libxrender
          libxtst
          libxscrnsaver
          mesa
          nspr
          nss
          alsa-lib
          at-spi2-atk
          at-spi2-core
          dbus
          expat
          fontconfig
          freetype
          libpciaccess

          # Additional libraries for newer Chromium versions
          libgbm
          libva
          libnotify
          speechd
          xdg-utils
          liberation_ttf

          # X11 libraries (for headless shell)
          libx11
          libxcomposite
          libxcursor
          libxdamage
          libxext
          libxfixes
          libxi
          libxrandr
          libxrender
          libxtst
          libxscrnsaver
          libxcb
          libxkbfile
          xorgproto
        ]);

      # Documentation
      etc."web-testing/README.md".text = ''
        # Web Testing Dependencies

        This module provides system libraries required for Playwright and Puppeteer
        to run on NixOS.

        ## What's Included

        - GTK/GNOME libraries for Chromium rendering
        - Font packages for proper text rendering
        - Audio/pipewire libraries for media playback
        - nix-ld configuration for dynamic library loading

        ## Usage

        After applying this configuration, Playwright tests should work:

        ```bash
        cd /data/@projects/frostbite-gazette
        npm run test
        playwright test
        ```

        ## Troubleshooting

        If you still get "library not found" errors:

        1. Rebuild the system: `sudo nixos-rebuild switch`
        2. Check nix-ld is enabled: `ls /run/current-system/sw/lib64`
        3. Test with a simple Node script:

        ```node
        const { chromium } = require('playwright');
        (async () => {
          const browser = await chromium.launch();
          console.log('Chromium launched successfully!');
          await browser.close();
        })();
        ```

        ## Notes

        - Playwright bundles its own Chromium binary
        - nix-ld allows that binary to find NixOS libraries
        - Some Playwright features may require additional configuration
      '';
    };

    # ============================================================================
    # NIX-LD FOR DYNAMIC LIBRARY LOADING
    # ============================================================================
    # Enable nix-ld to load libraries dynamically for bundled binaries
    programs.nix-ld = {
      enable = true;
      # Add libraries to the search path
      libraries = with pkgs; [
        # Core libraries
        stdenv.cc.cc.lib
        zlib
        glib
        glibc
        gtk3
        gtk4
        gdk-pixbuf
        pango
        cairo
        atk
        cups
        libdrm
        libxkbcommon
        libxrandr
        libxcb
        libxcomposite
        libxcursor
        libxdamage
        libxext
        libxfixes
        libxi
        libxrender
        libxtst
        libxscrnsaver
        mesa
        nspr
        nss
        alsa-lib
        at-spi2-atk
        at-spi2-core
        dbus
        expat
        fontconfig
        freetype
        libpciaccess
        libgbm
        libva
        libnotify

        # X11 libraries for headless shell
        libx11
        libxcomposite
        libxcursor
        libxdamage
        libxext
        libxfixes
        libxi
        libxrandr
        libxrender
        libxtst
        libxscrnsaver
        libxcb
        libxkbfile
        xorgproto
      ];
    };

    # ============================================================================
    # FONT CONFIGURATION
    # ============================================================================
    # Chromium needs fonts for proper rendering
    fonts.packages = with pkgs; [
      corefonts
      dejavu_fonts
      liberation_ttf
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
  };
}
