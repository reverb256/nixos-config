
{ ... }:

{
  desktop.plasma6.enable = false;

  programs.niri.enable = true;
  desktop.uwsm-sessions.enable = true;

  services.displayManager.defaultSession = "niri-uwsm";
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";
}
