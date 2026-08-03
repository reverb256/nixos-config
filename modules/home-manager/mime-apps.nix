# Centralized MIME type -> default application associations (NixOS/Home-Manager)
#
# Source of truth for xdg-mime defaults across the cluster.
#
# Design (per freedesktop mime-apps spec + Arch XDG MIME wiki):
#   - defaultApplications: app launched on double-click / xdg-open. Values are
#     LISTS so sibling modules (obsidian.nix scheme handler) can add without
#     clobbering — lists merge, scalars replace.
#   - associations.added (Added Associations): registers the app as "able to
#     open" the type. HM's xdg.mimeApps is STRICT: it only writes a default/
#     added entry when the target .desktop's own MimeType= lists the type
#     (freedesktop "a default must be associated" rule). Dev types therefore
#     route to helix-dev.desktop (see helix-desktop-entry.nix), whose MimeType
#     covers them — not the upstream Helix.desktop (which only lists
#     text/plain + application/x-shellscript).
#   - associations.removed: strips bogus self-associations (lmstudio claims
#     application/json).
#
# Every target .desktop is verified present in a known share dir.
{ ... }:

{
  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      # Browser + web scheme handlers
      "text/html" = [ "zen-twilight.desktop" ];
      "text/xml" = [ "zen-twilight.desktop" ];
      "application/xhtml+xml" = [ "zen-twilight.desktop" ];
      "x-scheme-handler/http" = [ "zen-twilight.desktop" ];
      "x-scheme-handler/https" = [ "zen-twilight.desktop" ];
      "x-scheme-handler/ftp" = [ "zen-twilight.desktop" ];
      "x-scheme-handler/about" = [ "zen-twilight.desktop" ];
      "x-scheme-handler/unknown" = [ "zen-twilight.desktop" ];
      "x-scheme-handler/webcal" = [ "zen-twilight.desktop" ];
      "x-scheme-handler/mailto" = [ "zen-twilight.desktop" ];
      "x-scheme-handler/irc" = [ "zen-twilight.desktop" ];

      # Images -> imv
      "image/png" = [ "imv.desktop" ];
      "image/jpeg" = [ "imv.desktop" ];
      "image/gif" = [ "imv.desktop" ];
      "image/webp" = [ "imv.desktop" ];
      "image/bmp" = [ "imv.desktop" ];
      "image/svg+xml" = [ "imv.desktop" ];
      "image/tiff" = [ "imv.desktop" ];

      # Video -> mpv
      "video/mp4" = [ "mpv.desktop" ];
      "video/x-matroska" = [ "mpv.desktop" ];
      "video/webm" = [ "mpv.desktop" ];
      "video/mpeg" = [ "mpv.desktop" ];
      "video/quicktime" = [ "mpv.desktop" ];
      "video/x-msvideo" = [ "mpv.desktop" ];

      # Audio -> mpv
      "audio/mpeg" = [ "mpv.desktop" ];
      "audio/ogg" = [ "mpv.desktop" ];
      "audio/x-wav" = [ "mpv.desktop" ];
      "audio/flac" = [ "mpv.desktop" ];
      "audio/x-m4a" = [ "mpv.desktop" ];

      "application/pdf" = [ "org.kde.okular.desktop" ];

      # Dev / plain text files -> helix-dev.desktop (declares these MimeTypes)
      "text/plain" = [ "helix-dev.desktop" ];
      "text/markdown" = [ "helix-dev.desktop" ];
      "text/csv" = [ "helix-dev.desktop" ];
      "text/x-log" = [ "helix-dev.desktop" ];
      "application/json" = [ "helix-dev.desktop" ];
      "application/toml" = [ "helix-dev.desktop" ];
      "application/x-yaml" = [ "helix-dev.desktop" ];
      "application/x-shellscript" = [ "helix-dev.desktop" ];
      "text/x-script" = [ "helix-dev.desktop" ];

      "inode/directory" = [ "org.kde.dolphin.desktop" ];
      "application/x-gnome-saved-search" = [ "org.kde.dolphin.desktop" ];
    };

    associations = {
      added = {
        "text/html" = [ "zen-twilight.desktop" ];
        "application/xhtml+xml" = [ "zen-twilight.desktop" ];
        "x-scheme-handler/http" = [ "zen-twilight.desktop" ];
        "x-scheme-handler/https" = [ "zen-twilight.desktop" ];

        "image/png" = [ "imv.desktop" ];
        "image/jpeg" = [ "imv.desktop" ];
        "image/gif" = [ "imv.desktop" ];
        "image/webp" = [ "imv.desktop" ];
        "image/bmp" = [ "imv.desktop" ];
        "image/svg+xml" = [ "imv.desktop" ];
        "image/tiff" = [ "imv.desktop" ];

        "video/mp4" = [ "mpv.desktop" ];
        "video/x-matroska" = [ "mpv.desktop" ];
        "video/webm" = [ "mpv.desktop" ];
        "video/mpeg" = [ "mpv.desktop" ];
        "video/quicktime" = [ "mpv.desktop" ];
        "video/x-msvideo" = [ "mpv.desktop" ];

        "audio/mpeg" = [ "mpv.desktop" ];
        "audio/ogg" = [ "mpv.desktop" ];
        "audio/x-wav" = [ "mpv.desktop" ];
        "audio/flac" = [ "mpv.desktop" ];
        "audio/x-m4a" = [ "mpv.desktop" ];

        "application/pdf" = [ "org.kde.okular.desktop" ];

        "text/plain" = [ "helix-dev.desktop" ];
        "text/markdown" = [ "helix-dev.desktop" ];
        "text/csv" = [ "helix-dev.desktop" ];
        "text/x-log" = [ "helix-dev.desktop" ];
        "application/json" = [ "helix-dev.desktop" ];
        "application/toml" = [ "helix-dev.desktop" ];
        "application/x-yaml" = [ "helix-dev.desktop" ];
        "application/x-shellscript" = [ "helix-dev.desktop" ];
        "text/x-script" = [ "helix-dev.desktop" ];

        "inode/directory" = [ "org.kde.dolphin.desktop" ];
      };
      removed = {
        "application/json" = [ "lmstudio.desktop" ];
      };
    };
  };
}
