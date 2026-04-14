# Nexus Desktop Configuration
# Niri Wayland compositor + SDDM + UWSM auto-login

{ ... }:

{
  # Plasma disabled — niri is the primary compositor
  desktop.plasma6.enable = false;

  # Niri + UWSM
  programs.niri.enable = true;
  desktop.uwsm-sessions.enable = true;

  # SDDM auto-login
  services.displayManager.defaultSession = "niri-uwsm";
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";
}
