# Nexus Desktop Configuration
# Niri Wayland compositor + SDDM auto-login
{ ... }:
{
  programs.niri.enable = true;
  desktop.uwsm-sessions.enable = true;
  services.displayManager.defaultSession = "niri";
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";
}
