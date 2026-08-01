{pkgs, lib, config, ...}: {
  options.programs.opencode.telegramDesktop = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Install Telegram Desktop in home.packages. Telegram is a Qt6 GUI app
      that pulls kcoreaddons -> pyside6 -> qtwebengine, i.e. a multi-hour
      Chromium source build. Headless hosts (sentry) set this to false.
    '';
  };

  config = {
    programs.opencode = {
      enable = true;
      settings = {
        plugin = ["oh-my-opencode@latest"];
      };
    };

    # Force overwrite to prevent backup collision errors
    xdg.configFile."opencode/opencode.json".force = true;

    home.packages = lib.optionals config.programs.opencode.telegramDesktop [pkgs.telegram-desktop];
  };
}
