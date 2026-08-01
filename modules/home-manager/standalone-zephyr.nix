{ pkgs, ... }:
{
  home.packages = with pkgs; [
    protonup-qt
    lutris
    heroic
    mangohud
    vkbasalt
  ];
}
