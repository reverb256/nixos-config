# Stylix + Base24 Hybrid Theming

This module provides a hybrid approach to theming that combines:
- **Stylix**: Automatic application theming (Base16 only, but with wide application support)
- **base16.nix**: Direct access to Base24 colors (8 additional bright colors)

## What is Base24?

Base24 extends Base16 with 8 additional colors (base10-base17) specifically designed for bright ANSI terminal colors:

| Color ID | Name | Purpose |
|----------|------|---------|
| base10 | Bright Red | Errors, important alerts |
| base11 | Bright Green | Success, additions |
| base12 | Bright Yellow | Warnings, highlights |
| base13 | Bright Blue | Links, info |
| base14 | Bright Magenta | Special keywords |
| base15 | Bright Cyan | Strings, types |
| base16 | Bright Black (Gray) | Secondary text |
| base17 | Bright White | Bright foreground |

## Usage

### Accessing Base24 Colors

The Base24 colors are exposed through two interfaces:

```nix
# In any NixOS or Home Manager module:
{ config, ... }:
{
  # Access via config.base24
  programs.kitty.settings = {
    # Use bright colors for bold text
    "color10" = "#${config.base24.base10}";  # Bright red
    "color11" = "#${config.base24.base11}";  # Bright green
    "color12" = "#${config.base24.base12}";  # Bright yellow
    "color13" = "#${config.base24.base13}";  # Bright blue
    "color14" = "#${config.base24.base14}";  # Bright magenta
    "color15" = "#${config.base24.base15}";  # Bright cyan
  };

  # Or access via config.stylix.base24 (same data, different path)
  home.file.".config/myapp/colors".text = ''
    bright_red=#${config.stylix.base24.base10}
    bright_green=#${config.stylix.base24.base11}
  '';
}
```

### Available Color Attributes

Each color provides multiple formats:

```nix
config.base24.base10    # "ff0000" (hex without #)
config.base24.base10-hex-r    # "ff" (red component)
config.base24.base10-hex-g    # "00" (green component)
config.base24.base10-hex-b    # "aa" (blue component)
config.base24.base10-dec-r    # "1.0" (red as decimal 0-1)
config.base24.base10-dec-g    # "0.0" (green as decimal 0-1)
config.base24.base10-dec-b    # "0.0" (blue as decimal 0-1)
config.base24.withHashtag.base10    # "#ff0000" (hex with #)
```

### Using True Base24 Schemes

By default, Stylix uses Base16 schemes. When using a Base16 scheme with this module, base16.nix automatically generates appropriate bright variants using fallback rules.

To use a true Base24 scheme with explicitly defined bright colors:

```nix
# In flake.nix or host configuration
stylix.base16Scheme = "${inputs.tinted-schemes}/base24/my-scheme.yaml";
```

Note: True Base24 schemes are less common than Base16 schemes. The tinted-schemes repository contains both.

### Example: Custom Terminal Configuration

```nix
{ config, pkgs, ... }:
{
  programs.alacritty.settings.colors = {
    # Primary colors from Stylix
    primary = {
      background = "#${config.lib.stylix.colors.base00}";
      foreground = "#${config.lib.stylix.colors.base05}";
    };
    
    # Normal colors (base16)
    normal = {
      black   = "#${config.lib.stylix.colors.base00}";
      red     = "#${config.lib.stylix.colors.base08}";
      green   = "#${config.lib.stylix.colors.base0B}";
      yellow  = "#${config.lib.stylix.colors.base0A}";
      blue    = "#${config.lib.stylix.colors.base0D}";
      magenta = "#${config.lib.stylix.colors.base0E}";
      cyan    = "#${config.lib.stylix.colors.base0C}";
      white   = "#${config.lib.stylix.colors.base05}";
    };
    
    # Bright colors (base24)
    bright = {
      black   = "#${config.base24.base16}";
      red     = "#${config.base24.base10}";
      green   = "#${config.base24.base11}";
      yellow  = "#${config.base24.base12}";
      blue    = "#${config.base24.base13}";
      magenta = "#${config.base24.base14}";
      cyan    = "#${config.base24.base15}";
      white   = "#${config.base24.base17}";
    };
  };
}
```

### Example: Waybar Custom Styling

```nix
{ config, ... }:
{
  programs.waybar.style = ''
    * {
      font-family: "${config.stylix.fonts.monospace.name}";
    }
    
    #workspaces button {
      color: #${config.lib.stylix.colors.base05};
    }
    
    #workspaces button.active {
      color: #${config.base24.base13};  /* Bright blue */
      border-bottom: 2px solid #${config.base24.base13};
    }
    
    #battery.warning {
      color: #${config.base24.base12};  /* Bright yellow */
    }
    
    #battery.critical {
      color: #${config.base24.base10};  /* Bright red */
    }
    
    #pulseaudio {
      color: #${config.base24.base11};  /* Bright green */
    }
  '';
}
```

## How It Works

1. **Stylix Configuration**: The `stylix.base16Scheme` option is set in `flake.nix` with a Base16/24 theme
2. **base16.nix Integration**: The `modules/stylix-base24.nix` module uses base16.nix to parse the scheme
3. **SchemeAttrs Generation**: `mkSchemeAttrs` processes the YAML scheme file and provides:
   - All 16 Base16 colors (base00-base0F)
   - All 24 Base24 colors (base00-base17, with base10-base17 being the bright variants)
   - Helper attributes (hex-r/g/b, dec-r/g/b, withHashtag)
4. **Exposure**: Colors are exposed through `config.base24` and `config.stylix.base24`

## Troubleshooting

### Colors don't match what I expect

When using a Base16 scheme (not Base24), the bright colors are auto-generated using fallback rules:
- Bright red (base10) = red (base08)
- Bright green (base11) = green (base0B)
- etc.

For true bright variants, use a Base24 scheme from `inputs.tinted-schemes`.

### Where are my colors?

Make sure the module is imported. In this configuration, it's imported via `common-base.nix` which imports `./modules/stylix-base24.nix`.

Access paths:
- `config.base24.*` - Direct access
- `config.stylix.base24.*` - Via Stylix namespace
- `config.lib.stylix.colors.*` - Standard Stylix colors (base00-base0F only)

## References

- [Base24 Specification](https://github.com/tinted-theming/base24/blob/master/styling.md)
- [base16.nix Documentation](https://github.com/SenchoPens/base16.nix/blob/main/DOCUMENTATION.md)
- [Stylix Documentation](https://stylix.danth.me/)
- [Tinted Theming Schemes](https://github.com/tinted-theming/schemes)
