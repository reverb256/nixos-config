{lib, ...}: {
  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications = {
    "text/html" = "zen-twilight.desktop";
    "text/xml" = "zen-twilight.desktop";
    "application/xhtml+xml" = "zen-twilight.desktop";
    "x-scheme-handler/http" = "zen-twilight.desktop";
    "x-scheme-handler/https" = "zen-twilight.desktop";
    "x-scheme-handler/ftp" = "zen-twilight.desktop";
    "x-scheme-handler/about" = "zen-twilight.desktop";
    "x-scheme-handler/unknown" = "zen-twilight.desktop";
    "x-scheme-handler/webcal" = "zen-twilight.desktop";
    "x-scheme-handler/mailto" = "zen-twilight.desktop";
    "x-scheme-handler/irc" = "zen-twilight.desktop";

    "image/png" = "imv.desktop";
    "image/jpeg" = "imv.desktop";
    "image/gif" = "imv.desktop";
    "image/webp" = "imv.desktop";
    "image/bmp" = "imv.desktop";
    "image/svg+xml" = "imv.desktop";
    "image/tiff" = "imv.desktop";

    "video/mp4" = "mpv.desktop";
    "video/x-matroska" = "mpv.desktop";
    "video/webm" = "mpv.desktop";
    "video/mpeg" = "mpv.desktop";
    "video/quicktime" = "mpv.desktop";
    "video/x-msvideo" = "mpv.desktop";

    "application/pdf" = "org.gnome.Evince.desktop";

    "inode/directory" = "org.kde.dolphin.desktop";
    "application/x-gnome-saved-search" = "org.kde.dolphin.desktop";
  };
}
