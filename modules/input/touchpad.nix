# Touchpad and Mouse Configuration Module
{pkgs, ...}: {
  # ============================================================================
  # LIBINPUT CONFIGURATION
  # ============================================================================
  #
  # This module configures libinput, which is used by Wayland compositors
  # (Hyprland, Niri, Sway, etc.) for touchpad and mouse input.
  #
  # ============================================================================

  # Install touchpad utilities
  environment.systemPackages = with pkgs; [
    libinput
    xf86-input-libinput
    touchegg # Multi-touch gesture recognizer
  ];

  # Libinput configuration for Wayland compositors
  services.libinput = {
    enable = true;

    # Touchpad configuration
    touchpad = {
      # Enable tap-to-click
      tappingButtonMap = "lmr"; # Left-middle-right button mapping
      tappingDragLock = false; # Disable drag lock
      middleEmulation = false;

      # Natural scrolling
      naturalScrolling = false;

      # Disable while typing
      disableWhileTyping = true;

      # Speed and sensitivity
      accelSpeed = "0.5"; # -1.0 to 1.0 (0 is unaccelerated)
      accelProfile = "adaptive"; # flat or adaptive

      # Scroll method
      scrollMethod = "twofinger"; # none, edge, twofinger, button, on-button-down

      # Click methods
      clickMethod = "clickfinger"; # none, button-area, clickfinger
    };

    # Mouse configuration
    mouse = {
      # Natural scrolling
      naturalScrolling = false;

      # Acceleration
      accelSpeed = "0.5";
      accelProfile = "adaptive";

      # Middle button emulation
      middleEmulation = false;
    };
  };

  # ============================================================================
  # HYPRLAND CONFIGURATION
  # ============================================================================
  #
  # Configure Hyprland touchpad in ~/.config/hypr/hyprland.conf:
  #
  # input {
  #   touchpad {
  #     natural_scroll = true
  #     disable_while_typing = true
  #     tap-to-click = true
  #   }
  # }
  #
  # ============================================================================

  # ============================================================================
  # NIRI CONFIGURATION
  # ============================================================================
  #
  # Configure Niri touchpad in ~/.config/niri/config.kdl:
  #
  # input {
  #   touchpad {
  #     tap-to-click = true
  #     dwt = true
  #     disable-while-typing = true
  #     natural-scroll = true
  #   }
  # }
  #
  # ============================================================================

  # Touch gestures (optional)
  # services.touchegg.enable = true;
}
