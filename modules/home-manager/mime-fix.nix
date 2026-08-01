# MIME/desktop file fix for NixOS
#
# Problem: app launchers (Noctalia, KDE/Dolphin pickers) only scan a fixed set
# of XDG applications dirs — they do NOT honor $XDG_DATA_DIRS dynamically for
# the user nix profile. So .desktop files from:
#   - system packages  (/run/current-system/sw/share/applications)
#   - nix profile apps (~/.nix-profile/share/applications, e.g. `nix profile
#     install` of lutris, remote-viewer, ...)
# fail to surface unless they are also present in ~/.local/share/applications.
#
# Note: app discovery is purely filesystem (freedesktop Desktop Entry spec) —
# there is no portal/socket/D-Bus registration. The bridge is symlinking into
# the launcher's scanned dir + regenerating mimeinfo.cache.
#
# Fix:
#   1) symlink system + nix-profile .desktop files into ~/.local/share/applications/
#   2) run update-desktop-database to regenerate mimeinfo.cache
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) hm;
in {
  home.activation.mimeDesktopFix = hm.dag.entryAfter ["writeBoundary"] ''
    set -euo pipefail

    LOCAL_APPS="$HOME/.local/share/applications"
    SYSTEM_APPS="/run/current-system/sw/share/applications"
    NIXPROFILE_APPS="$HOME/.nix-profile/share/applications"

    # Create local applications directory if it doesn't exist
    mkdir -p "$LOCAL_APPS"

    # Symlink .desktop files from system packages that aren't already present
    # locally. Makes them visible to launchers and xdg-mime query.
    if [ -d "$SYSTEM_APPS" ]; then
      for desktop in "$SYSTEM_APPS"/*.desktop; do
        [ -e "$desktop" ] || continue
        basename=$(basename "$desktop")
        if [ ! -e "$LOCAL_APPS/$basename" ]; then
          ln -sfn "$desktop" "$LOCAL_APPS/$basename"
        fi
      done
    fi

    # Symlink ALL .desktop files from the user nix profile. `nix profile
    # install` lands GUI apps here, but launchers don't scan this dir on their
    # own (zen-twilight, lutris, remote-viewer, etc.). Mirror
    # the system loop so every profile-installed GUI app surfaces automatically.
    if [ -d "$NIXPROFILE_APPS" ]; then
      for desktop in "$NIXPROFILE_APPS"/*.desktop; do
        [ -e "$desktop" ] || continue
        basename=$(basename "$desktop")
        if [ ! -e "$LOCAL_APPS/$basename" ]; then
          ln -sfn "$desktop" "$LOCAL_APPS/$basename"
        fi
      done
    fi

    # Regenerate mimeinfo.cache so xdg-mime and launchers find the entries
    UPDATE_DB="${pkgs.desktop-file-utils}/bin/update-desktop-database"
    if [ -x "$UPDATE_DB" ]; then
      "$UPDATE_DB" "$LOCAL_APPS" 2>/dev/null || true
    fi

    echo "MIME fix: symlinked desktop files and regenerated mimeinfo.cache"
  '';
}
