# Keyboard Configuration Module
{pkgs, ...}: {
  # Keyboard settings
  # Note: Display manager (SDDM) requires services.xserver.enable = true
  # XKB settings are handled by Wayland compositors, not here
  services.xserver = {
    xkb.layout = "us";
    xkb.options = "ctrl:nocaps";
  };

  # System keyboard configuration
  # These are the defaults - Hyprland/Niri can override per-config
  environment.sessionVariables = {
    # Keyboard layout
    XKB_DEFAULT_LAYOUT = "us";
    XKB_DEFAULT_VARIANT = "";

    # Keyboard options (combine capslock->ctrl with terminate shortcut)
    XKB_DEFAULT_OPTIONS = "ctrl:nocaps,terminate:ctrl_alt_bksp";
  };

  # Install keyboard utilities
  environment.systemPackages = with pkgs; [
    keyd # Keyboard remapping daemon
    interception-tools # Keyboard interception for complex mappings
  ];

  # ============================================================================
  # KEYBOARD CONFIGURATION NOTES
  # ============================================================================
  #
  # **Caps Lock as Ctrl:**
  # - Set via XKB_DEFAULT_OPTIONS above
  # - Works in both Hyprland and Niri
  #
  # **Custom Keymaps:**
  # - Use keyd for complex remapping (multi-layer, etc.)
  # - Enable with services.keyd.enable = true;
  #
  # **Per-Keyboard Configuration:**
  # - Hyprland: Set in ~/.config/hypr/hyprland.conf
  #   input {
  #     kb_layout = us
  #     kb_options = ctrl:nocaps
  #   }
  # - Niri: Set in ~/.config/niri/config.kdl
  #   input.keyboard.repeat-delay = 300;
  #   input.keyboard.repeat-rate = 50;
  #
  # ============================================================================
}
