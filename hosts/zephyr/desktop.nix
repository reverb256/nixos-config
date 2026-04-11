# Zephyr Desktop and Display Configuration
# Wayland compositors (niri, hyprland), Plasma auto-login, HDR, flatpak
# SDDM session picker available for compositor switching
{ pkgs, lib, ... }:
{
  # ============================================================================
  # DESKTOP - Wayland compositors (select via SDDM session picker)
  # ============================================================================
  desktop.uwsm-sessions.enable = true;
  programs.niri.enable = true;
  programs.hyprland.enable = true;

  # Autologin into Plasma on boot. To switch compositor, logout
  # and pick from SDDM's session picker.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";
  services.displayManager.defaultSession = "plasma";

  # ============================================================================
  # GAMING HDR - 4K HDR TV support
  # ============================================================================
  services.gaming.hdr.enable = true;

  # ============================================================================
  # FLATPAK - Flatpak support with Discover and Flathub
  # ============================================================================
  services.flatpak-kde = {
    enable = true;
    autoUpdate = true;
  };

  # ============================================================================
  # SPOTIFY - SpotX patch (ad-free, premium features)
  # ============================================================================
  services.spotify-spotx = {
    enable = true;
    forceX11 = true;
    clearCacheOnPatch = true;
  };

  # ============================================================================
  # MULTIMEDIA - GStreamer support for Qt/KDE applications
  # ============================================================================
  services.multimedia.gstreamer.enable = true;
}
