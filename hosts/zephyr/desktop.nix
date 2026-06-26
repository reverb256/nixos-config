{
  pkgs,
  lib,
  ...
}: {
  # No display manager — getty autologin on tty1, niri started via uwsm
  services.getty.autologinUser = "j_kro";

  # Disable xserver/display-manager infrastructure — pure Wayland from TTY
  services.xserver.enable = lib.mkForce false;

  desktop.uwsm-sessions.enable = true;
  programs.niri.enable = true;

  services.gaming.hdr.enable = true;
  services.gaming.vr.enable = true;

  programs.gamescope.enable = true;
  services.gaming.gamescopeSession = {
    enable = true;
    vkDeviceFilter = "10de:2204"; # RTX 3090 — prevents Vulkan from touching the 3060 Ti
  };

  services.flatpak-kde = {
    enable = true;
    autoUpdate = true;
  };

  services.spotify-spotx = {
    enable = true;
    forceX11 = true;
    clearCacheOnPatch = true;
  };

  services.multimedia.gstreamer.enable = true;
}
