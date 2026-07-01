{ config, pkgs, lib, ... }: {

  programs.alacritty = {
    enable = true;

    # Stylix auto-imports alacritty config - preserve selection settings
    # Stylix uses lib.mkMerge internally, so these settings are merged into generated config
    settings = {
      # Fix Alacritty 0.17.0 deprecation warning: shell → terminal.shell
      terminal.shell.program = "fish";
      terminal.osc52 = "CopyPaste";

      selection.save_to_clipboard = true;
    };
  };
}
