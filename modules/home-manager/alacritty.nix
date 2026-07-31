{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.alacritty = {
    enable = true;

    # Stylix auto-imports alacritty config - preserve selection settings
    # Stylix uses lib.mkMerge internally, so these settings are merged into generated config
    settings = {
      # Fix Alacritty 0.17.0 deprecation warning: shell → terminal.shell
      terminal.shell.program = "fish";
      terminal.osc52 = "CopyPaste";

      selection.save_to_clipboard = true;

      # Noctalia personalization (matches the hand-managed alacritty.toml we
      # reclaim during the standalone-HM extraction — no regression).
      # The noctalia theme file is written by stylix-bridges.nix (HM-managed).
      general.import = [ "~/.config/alacritty/themes/noctalia.toml" ];
      font.size = 10;
      font.normal.family = "JetBrainsMono Nerd Font";
      font.normal.style = "Regular";
      window.opacity = 0.95;
    };
  };
}
