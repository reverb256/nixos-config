# Nexus Desktop Configuration
# Niri Wayland compositor + Plasma for gaming, Steam Gamescope session
{ ... }:
{
  # Enable workstation role for full Plasma desktop environment
  profiles.role.workstation = true;

  # Autologin into Niri on boot (instead of Plasma)
  programs.niri.enable = true;
  services.displayManager.defaultSession = "niri";
}
