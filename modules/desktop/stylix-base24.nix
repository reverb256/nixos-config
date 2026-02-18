# Stylix + Base24 Hybrid Theming Module for NixOS
#
# This module provides a hybrid approach:
# - Stylix for automatic application theming (base16 only)
# - base16.nix for direct access to Base24 colors (8 additional bright colors)
#
# Usage:
#   - Stylix colors: config.lib.stylix.colors.base00
#   - Base24 colors: config.base24.base10 (bright red), base11 (bright green), etc.

{ pkgs, lib, config, inputs, ... }:

let
  # Import base16.nix library functions
  base16Lib = inputs.base16.lib { inherit pkgs lib; };

  # Base24 adds 8 additional colors (base10-base17) for bright ANSI colors:
  # base10 = bright red, base11 = bright green, base12 = bright yellow
  # base13 = bright blue, base14 = bright magenta, base15 = bright cyan
  # base16 = bright black (gray), base17 = bright white
  #
  # When a base16 scheme is loaded, base16.nix generates base24-compatible
  # values using fallback rules (bright variants derived from base colors)

  # Get the currently configured Stylix scheme
  stylixScheme = config.stylix.base16Scheme;

  # Generate full Base24 scheme attrs using base16.nix
  # This provides access to base10-base17 (bright colors)
  base24Scheme = base16Lib.mkSchemeAttrs stylixScheme;
in
{
  # Expose Base24 colors through a convenient interface
  # Access via: config.base24.base10, config.base24.base11, etc.
  options.base24 = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    description = ''
      Base24 color scheme attributes. Provides access to 24 colors total:
      - base00-base0F: Standard base16 colors (same as Stylix)
      - base10-base17: Additional bright colors for ANSI terminals

      Common usage:
        config.base24.base10  # Bright red
        config.base24.base11  # Bright green
        config.base24.base12  # Bright yellow
        config.base24.base13  # Bright blue
        config.base24.base14  # Bright magenta
        config.base24.base15  # Bright cyan

      Note: If using a true Base24 scheme file, these will be the actual defined
      bright colors. If using a Base16 scheme, base16.nix generates appropriate
      bright variants using fallback rules.
    '';
  };

  config.base24 = base24Scheme;

  # Also expose through stylix interface for convenience
  options.stylix.base24 = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    description = ''
      Base24 color palette extension for Stylix.
      Access bright colors (base10-base17) that extend the standard base16 palette.
    '';
  };

  config.stylix.base24 = lib.mkIf config.stylix.enable base24Scheme;
}
