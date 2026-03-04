# KDE Plasma 6 Desktop Environment
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Enable the X11 windowing system
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Enable auto-login for j_kro
  services.displayManager.autoLogin = {
    enable = true;
    user = "j_kro";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Qt 6 environment variables to fix RHI/GLES2 issues and KWin stability
  environment.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    QT_USE_RHI_GLES2 = "1";
    QT_QPA_GL_VERSION = "2"; # Force OpenGL 2.0 for better compatibility
    KWIN_DRM_DEVICE = "/dev/dri/card0"; # Prefer primary GPU
    KWIN_DRM_PRIMARY = "1";
  };
}
