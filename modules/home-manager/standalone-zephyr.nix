{ pkgs, ... }:
{
  xdg.configFile."wayfire/wayfire.ini".source = ../../desktop/wayfire.ini;
  xdg.configFile."wlogout/layout".source = ../../desktop/wlogout-layout;

  home.packages = with pkgs; [
    protonup-qt
    lutris
    heroic
    mangohud
    vkbasalt
  ];

  programs.steam.enable = true;
  programs.discord.enable = true;
  programs.obs-studio.enable = true;

  home.file.".local/share/Steam/steamapps/common".source = pkgs.linkFarm "steam-games" {};
}
