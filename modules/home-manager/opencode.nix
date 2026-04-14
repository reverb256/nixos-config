{pkgs, ...}: {
  programs.opencode = {
    enable = true;
    settings = {
      plugin = ["oh-my-opencode@latest"];
    };
  };

  home.packages = [pkgs.telegram-desktop];
}
