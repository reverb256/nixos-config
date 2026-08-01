{ config, pkgs, lib, ... }:
{
  programs.alacritty = {
    enable = true;

    # Stylix auto-imports alacritty config - preserve selection settings
    # Stylix uses lib.mkMerge internally, so these settings are merged into generated config
    settings = {
      # Fix Alacritty 0.17.0 deprecation warning: shell → terminal.shell
      terminal.shell.program = "fish";
      terminal.osc52 = "CopyPaste";

      # Pin terminal font size to 10 to match the stylix `terminal = 10` token
      # (modules/desktop/stylix.nix). This stylix version sets the alacritty
      # font *family* (JetBrainsMono Nerd Font, via stylix.fonts.monospace) but
      # emits a default point size of 12 for alacritty, so the size must be set
      # explicitly here to harmonize with the rest of the themed session.
      font.size = 10;

      selection.save_to_clipboard = true;
    };
  };
}
