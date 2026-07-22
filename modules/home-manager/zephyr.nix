# Zephyr Home-Manager Configuration
# Workstation, control plane, gaming
{
  config,
  lib,
  pkgs,
  ...
}: {
  home-manager.users.j_kro = {pkgs, ...}: {
    # Gaming desktop environment
    xdg.configFile."wayfire/wayfire.ini".source = ../../desktop/wayfire.ini;
    xdg.configFile."wlogout/layout".source = ../../desktop/wlogout-layout;

    # Gaming tools
    home.packages = with pkgs; [
      protonup-qt
      lutris
      heroic
      mangohud
      vkbasalt
    ];

    # Steam configuration (if enabled)
    programs.steam.enable = true;

# Discord
    programs.discord.enable = true;

    # OBS Studio (for streaming)
    programs.obs-studio.enable = true;

    # Development tools (gaming-related)
    home.file.".local/share/Steam/steamapps/common".source = pkgs.linkFarm "steam-games" {
      # Games are managed declaratively, but installed to standard location
    };
  };
}
