{pkgs, ...}: {
  programs.opencode = {
    enable = true;
    settings = {
      plugin = ["oh-my-opencode@latest"];
    };
  };

  # Force overwrite to prevent backup collision errors
  xdg.configFile."opencode/opencode.json".force = true;

  home.packages = [pkgs.telegram-desktop];
}
