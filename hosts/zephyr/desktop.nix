{
  pkgs,
  lib,
  ...
}: {
  services.displayManager.sddm.enable = lib.mkForce true;
  services.displayManager.sddm.wayland.enable = true;

  desktop.uwsm-sessions.enable = true;
  programs.niri.enable = true;

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";
  services.displayManager.defaultSession = "niri-uwsm";

  services.gaming.hdr.enable = true;
  services.gaming.vr.enable = true;

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
