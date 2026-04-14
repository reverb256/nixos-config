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
    environment = {
      sessionVariables.PLAYWRIGHT_BROWSERS_PATH = "/home/j_kro/playwright-browsers";

      systemPackages = with pkgs;
        [
          playwright
        ]
        ++ (with pkgs; [
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
          speechd
          xdg-utils
          liberation_ttf

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

      etc."web-testing/README.md".text = ''

        This module provides system libraries required for Playwright and Puppeteer
        to run on NixOS.


        - GTK/GNOME libraries for Chromium rendering
        - Font packages for proper text rendering
        - Audio/pipewire libraries for media playback
        - nix-ld configuration for dynamic library loading


        After applying this configuration, Playwright tests should work:

        ```bash
        cd /data/@projects/frostbite-gazette
        npm run test
        playwright test
        ```


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


        - Playwright bundles its own Chromium binary
        - nix-ld allows that binary to find NixOS libraries
        - Some Playwright features may require additional configuration
      '';
    };

    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
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
