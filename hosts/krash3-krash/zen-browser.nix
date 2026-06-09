{ inputs, lib, ... }:
{
  imports = [ inputs.zen-browser.homeModules.twilight-official ];

  programs.zen-browser = {
    enable = true;
    setAsDefaultBrowser = true;

    # Policies (baked into the package, not the profile)
    policies = {
      DisableAppUpdate = true;
      DisableTelemetry = true;
      DisablePocket = true;
      DisableFirefoxSync = true;
      DisableFirefoxAccounts = true;
      SanitizeOnShutdown = {
        Cache = true;
        Cookies = true;
        History = false;
        Sessions = false;
        OfflineApps = true;
      };
    };

    # No declarative profile config — we use the Windows profile directly
    # via the symlink below (home.file.".config/zen"). This means:
    #   - krash's existing Windows Zen profile (extensions, bookmarks,
    #     history, settings) is shared between Windows Zen and WSLg Zen
    #   - Changes made in either are visible in the other
    #   - Do NOT run both simultaneously (profile locking)
    profiles."Default (release)" = {
      id = 0;

      # Only accessibility prefs — these adapt the Windows profile
      # for the larger WSLg display and krash's needs
      settings = {
        "layout.css.devPixelsPerPx" = "1.33";
        "font.size.variable.x-western" = 18;
        "font.size.fixed.x-western" = 16;
        "browser.zoom.full" = true;
      };
    };
  };

  # Symlink ~/.config/zen -> Windows Zen roaming profile
  # This makes the WSLg Zen browser use the exact same profile data as
  # krash's native Windows Zen browser
  home.file.".config/zen" = {
    source = "/mnt/c/Users/krash/AppData/Roaming/Zen";
    force = true;
  };
}
