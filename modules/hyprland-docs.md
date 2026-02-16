# Hyprland Configuration Documentation

## Overview

This cluster uses a dual desktop environment setup:
- **Plasma 6** - Available as default for users who prefer a full DE
- **Hyprland** - Tiling Wayland compositor, configurable as alternative

## Configuration Files

### 1. Module Files

**`modules/hyprland.nix`**
- Hyprland compositor configuration
- Required packages: waybar, rofi, grim, slurp, wl-clipboard, wlogout, www

**`modules/hyprland-stylix.nix`**
- Stylix integration for Hyprland theming
- Generates color definitions from Stylix Base16/Base24 themes
- Options:
  ```nix
  hyprland.stylixIntegration = true;
  ```

**`modules/hyprland-monitors.nix`**
- Explicit monitor configuration module
- Allows defining monitors with specific properties (resolution, refresh rate, scaling, etc.)
- Options:
  ```nix
  monitors = [
    {
      name = "DP-1";
      width = 2560;
      height = 1440;
      refreshRate = 144;
      scale = 1.0;
    }
  ];
  ```

### 2. User Configuration

**Home Directory Structure:**
```
~/.config/hyprland/
├── hyprland.conf          # Main Hyprland configuration
├── monitors.conf           # Explicit monitor rules (auto-generated)
├── colors.conf             # Stylix color variables (auto-generated)
└── colors-theme.source   # Stylix theme source (auto-generated)
```

## Stylix Integration

### Enabling Stylix Theming

To enable automatic Stylix colors for Hyprland:

1. In `hosts/<host>/configuration.nix`:
   ```nix
   imports = [
     ../../modules/hyprland.nix
     ../../modules/hyprland-stylix.nix
   ];
   
   # Enable Stylix integration
   programs.hyprland.enable = true;
   # or
   programs.hyprland.stylixIntegration = true;  # If using custom module
   ```

2. In your `hyprland.conf`, source the theme file:
   ```
   source = ~/.config/hyprland/colors-theme.source
   ```

### Available Colors

**Base16 Colors (Standard):**
- `config.lib.stylix.colors.base00-0F` - Standard palette (16 colors)
- `config.stylix.base24.base00-0F` - Same as above via Base24 interface

**Base24 Colors (Bright Variants):**
- `config.stylix.base24.base10-17` - Bright colors
  - base10: Bright red
  - base11: Bright green
  - base12: Bright yellow
  - base13: Bright blue
  - base14: Bright magenta
  - base15: Bright cyan
  - base16: Bright black
  - base17: Bright white

### Manual Color Usage in Hyprland

If you want to manually set colors in your hyprland.conf:

```bash
# Source the color definitions
source ~/.config/hyprland/colors.conf

# Use in decoration section
decoration {
    col.active_border = $col.active_border
    col.inactive_border = $col.inactive_border
}
```

## Monitor Configuration

### Explicit Monitor Setup

To configure monitors explicitly:

1. Add the module to your host config:
   ```nix
   imports = [ ... ];
   
   monitors = [
     {
       name = "DP-1";
       width = 2560;
       height = 1440;
       refreshRate = 144;
       scale = 1.0;
       transform = 0;  # 0=normal, 1=90°, 2=180°, 3=270°
     }
     {
       name = "HDMI-1";
       width = 1920;
       height = 1080;
       refreshRate = 60;
     }
   ];
   ```

### Benefits of Explicit Configuration

- **Reproducibility** - Same setup every time
- **Predictable** - No reliance on auto-detection
- **Multi-monitor** - Better control over monitor-specific workspaces
- **Hyprland rules** - Can create monitor-specific window rules

### Auto-generated Configuration Files

The module automatically generates:

1. **`~/.config/hyprland/monitors.conf`**
   - Contains Hyprland monitor rules
   - Generated from `monitors` option

2. **`~/.config/hyprland/colors.conf`**
   - Contains Stylix color variable definitions
   - Example: `col.active_border=rgba(33ccff)`

3. **`~/.config/hyprland/colors-theme.source`**
   - Source file to include in main hyprland.conf
   - Contains: `source = ~/.config/hyprland/colors-theme.source`

### Applying Monitor Changes

After changing `monitors` option, run:
```bash
# Restart Hyprland to apply new configuration
hyprctl reload config

# Or use the provided script
~/.local/bin/hyprland-apply-monitors
```

## Usage Examples

### Example 1: Single Monitor (Auto-detection)

```nix
# configuration.nix
{
  imports = [
    ./modules/hyprland.nix
    ./modules/hyprland-stylix.nix  # For theming
  ];
  
  programs.hyprland.enable = true;
}
```

### Example 2: Dual Monitors (Explicit)

```nix
# configuration.nix
{
  imports = [
    ./modules/hyprland.nix
    ./modules/hyprland-monitors.nix
    ./modules/hyprland-stylix.nix  # For theming
  ];
  
  monitors = [
    {
      name = "DP-1";
      enabled = true;
      width = 2560;
      height = 1440;
      refreshRate = 144;
      workspace = 1;  # Workspace 1 for this monitor
    }
    {
      name = "HDMI-1";
      enabled = true;
      width = 1920;
      height = 1080;
      refreshRate = 60;
      workspace = 2;  # Workspace 2 for this monitor
    }
  ];
}
```

### Example 3: Using Stylix Colors Manually

In your `hyprland.conf`:
```bash
# Add to general section
source = ~/.config/hyprland/colors-theme.source

# Use colors in decoration section
decoration {
    col.active_border = $col.active_border
    col.inactive_border = $col.inactive_border
    
    col.bg = $col.bg  # Background color
}
```

## Troubleshooting

### Colors not applying

If Hyprland isn't using Stylix colors:

1. Check if Stylix integration is enabled
2. Verify `colors-theme.source` file exists
3. Check if your main hyprland.conf sources it

```bash
# Check Stylix integration status
nix-store -q --query 'requisites' --file ~/.local/state/home-manager/home.packages.drv | grep hyprland

# Verify colors file
cat ~/.config/hyprland/colors-theme.source
```

### Monitor configuration not applying

1. Verify monitors are defined in `monitors` option
2. Check if `~/.config/hyprland/monitors.conf` exists
3. Run `hyprctl monitors` to see current configuration

```bash
# Check monitor rules
hyprctl monitors

# Manually reload
hyprctl reload config
```

### Switching Between Plasma and Hyprland

To switch desktop environments:

**Log out:**
- In SDDM (display manager), select the desired environment at login
- Both environments will use the same Stylix colors

**Disable unused environment:**
- If using Hyprland, Plasma services (KDE Portal, KWin) won't interfere
- If using Plasma, Hyprland won't start

## Module Interaction

The three modules work together:

1. **`modules/hyprland.nix`** - Core Hyprland setup and packages
2. **`modules/hyprland-stylix.nix`** - Extends Hyprland with Stylix theming
3. **`modules/hyprland-monitors.nix`** - Explicit monitor configuration

All can be imported independently or together.

## Related Documentation

- [modules/stylix-base24.md](./stylix-base24.md) - Stylix + Base24 integration guide
- [Stylix Documentation](https://stylix.danth.me/) - Official Stylix docs
- [Hyprland Wiki](https://wiki.hypr.land/) - Official Hyprland documentation
