{ lib, pkgs, ... }:
{
  # Symlink ~/.config/zen -> Windows profile so WSLg Zen uses
  # krash's existing Windows Zen profile directly.
  home.activation.createZenSymlink = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -L "''${HOME}/.config/zen" ] && [ -d "/mnt/c/Users/krash/AppData/Roaming/Zen" ]; then
      if [ -d "''${HOME}/.config/zen" ]; then
        rm -rf "''${HOME}/.config/zen"
      fi
      ln -sf "/mnt/c/Users/krash/AppData/Roaming/Zen" "''${HOME}/.config/zen"
      $VERBOSE_ECHO "zen: symlinked ~/.config/zen -> Windows profile"
    fi
  '';

  # Accessibility — larger UI for krash (older person)
  home.file.".config/zen/user-overrides.js" = {
    text = ''
      // Krash accessibility overrides
      user_pref("layout.css.devPixelsPerPx", "1.33");
      user_pref("font.size.variable.x-western", 18);
      user_pref("font.size.fixed.x-western", 16);
      user_pref("browser.zoom.full", true);
    '';
    force = true;
  };
}
