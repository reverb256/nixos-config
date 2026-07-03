# MIME/desktop file fix for NixOS
#
# Problem: system packages install .desktop files to
# /run/current-system/sw/share/applications/ but the user's local
# mimeinfo.cache isn't regenerated, so Dolphin/KDE file pickers
# show empty lists and "remember app" doesn't persist.
#
# Fix:
#   1) symlink system .desktop files into ~/.local/share/applications/
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

    # Symlink .desktop files from system packages that aren't already present locally.
    # This makes them visible to KDE/Dolphin file pickers and xdg-mime query.
    if [ -d "$SYSTEM_APPS" ]; then
      for desktop in "$SYSTEM_APPS"/*.desktop; do
        [ -e "$desktop" ] || continue
        basename=$(basename "$desktop")
        if [ ! -e "$LOCAL_APPS/$basename" ]; then
          ln -sfn "$desktop" "$LOCAL_APPS/$basename"
        fi
      done
    fi

    # Ensure zen-twilight.desktop is always present (comes from HM packages, not
    # system packages, so may need manual restoration after HM profile changes)
    if [ -f "$NIXPROFILE_APPS/zen-twilight.desktop" ]; then
      ln -sf "$NIXPROFILE_APPS/zen-twilight.desktop" \
        "$LOCAL_APPS/zen-twilight.desktop"
    fi

    # Regenerate mimeinfo.cache so xdg-mime and KDE pickers find the entries
    UPDATE_DB="${pkgs.desktop-file-utils}/bin/update-desktop-database"
    if [ -x "$UPDATE_DB" ]; then
      "$UPDATE_DB" "$LOCAL_APPS" 2>/dev/null || true
    fi

    echo "MIME fix: symlinked desktop files and regenerated mimeinfo.cache"
  '';
}