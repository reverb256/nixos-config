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
      # (modules/desktop/stylix.nix). Stylix's alacritty target hardcodes
      # font.size = 12, so force our value to harmonize the graphical terminal
      # with the rest of the themed session. Family (JetBrainsMono Nerd Font)
      # is already supplied by stylix.fonts.monospace.
      font.size = lib.mkForce 10;

      selection.save_to_clipboard = true;
    };
  };
}
