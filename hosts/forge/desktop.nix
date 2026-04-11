# Forge Desktop Configuration
# Wayland via niri + SDDM + auto-login (minimal desktop for mining rig)
{ ... }:
{
  # Desktop — Wayland only via niri + SDDM + uwsm
  programs.niri.enable = true;
  desktop.uwsm-sessions.enable = true;
  services.displayManager.defaultSession = "niri";
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";
}
