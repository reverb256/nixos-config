{ config, pkgs, lib, ... }:
let
  c = config.lib.stylix.colors.withHashtag;
  skinFile = pkgs.writeText "stylix.yaml" (builtins.toJSON {
    name = "stylix";
    description = "Auto-generated from Stylix theme";

    colors = {
      banner_border = c.base0D;
      banner_title = c.base0D;
      banner_accent = c.base0C;
      banner_dim = c.base03;
      banner_text = c.base05;

      ui_accent = c.base0D;
      ui_label = c.base0A;
      ui_ok = c.base0B;
      ui_error = c.base08;
      ui_warn = c.base09;

      prompt = c.base05;
      input_rule = c.base04;
      response_border = c.base0D;

      status_bar_bg = c.base01;
      status_bar_text = c.base04;
      status_bar_strong = c.base0D;
      status_bar_dim = c.base03;
      status_bar_good = c.base0B;
      status_bar_warn = c.base0A;
      status_bar_bad = c.base09;
      status_bar_critical = c.base08;

      session_label = c.base0A;
      session_border = c.base03;

      voice_status_bg = c.base01;
      selection_bg = c.base02;

      completion_menu_bg = c.base00;
      completion_menu_current_bg = c.base02;
      completion_menu_meta_bg = c.base00;
      completion_menu_meta_current_bg = c.base02;
    };
  });
in {
  home.file.".hermes/skins/stylix.yaml" = {
    source = skinFile;
    force = true;
  };

  # Set stylix as the active skin in hermes config
  # This is a lower-priority default so user can still /skin to something else
}
