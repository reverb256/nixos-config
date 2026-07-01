{ config, pkgs, lib, ... }: {

  programs.alacritty = {
    enable = true;

    # Stylix auto-imports alacritty config - preserve selection settings
    # Stylix uses lib.mkMerge internally, so these settings are merged into generated config
    settings = {
      selection.save_to_clipboard = true;
    };
  };
}
