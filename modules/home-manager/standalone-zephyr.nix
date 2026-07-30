{ pkgs, ... }:
{
  home.packages = with pkgs; [
    protonup-qt
    lutris
    heroic
    mangohud
    vkbasalt
  ];

  home.file.".local/share/Steam/steamapps/common".source = pkgs.linkFarm "steam-games" {};
}
