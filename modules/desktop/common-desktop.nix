{pkgs, ...}: {
  # Common desktop configuration for niri + uwsm + flatpak
  # Used by nexus, forge, sentry (and potentially other desktop hosts)
  # Zephyr has its own extended desktop.nix with gaming/VR/HDR additions

  programs.niri.enable = true;
  desktop.uwsm-sessions.enable = true;

  services.displayManager.defaultSession = "niri-uwsm";
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";

  services.flatpak.enable = true;

