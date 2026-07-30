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


  home.file.".local/share/Steam/steamapps/common".source = pkgs.linkFarm "steam-games" {};
}
