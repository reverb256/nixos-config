# Hyprland + Plasma Dual Desktop Setup

## Overview

This configuration provides **both Plasma 6 and Hyprland** desktop environments on your NixOS system. You can switch between them at the SDDM login screen.

## What's Configured

### **Plasma 6** (Default)
- Full KDE desktop environment
- System settings, widgets, KDE Connect
- Suitable for daily use, gaming, VR

### **Hyprland** (Alternative)
- Tiling Wayland compositor
- Keyboard-driven workflow
- Lightweight and fast
- Perfect for development work

## Module Structure

```
modules/desktop/hyprland/
├── home.nix           # Main Home Manager entry point
├── settings.nix       # Core Hyprland settings
├── binds.nix          # All keybindings
├── windowrules.nix    # Window behavior rules
└── variables.nix      # Theme variables (Stylix integration)
```

## Key Features

### **Stylix Integration**
- Automatic theming from your Tokyo City Dark theme
- Colors sync across both desktop environments
- Window borders match your system theme

### **Smart Keybindings** (Omarchy-inspired)
- `SUPER+Return` → Kitty terminal
- `SUPER+W` → Close window
- `SUPER+D` → Application launcher (rofi)
- `SUPER+F` → Toggle fullscreen
- `HJKL` or Arrows → Vim-style window navigation
- `SUPER+1-0` → Switch workspaces (uses code:10-19)
- `Print` → Screenshot (copy to clipboard)
- `SUPER+Print` → Screenshot region selection
- `SUPER+S` → Toggle scratchpad workspace
- `SUPER+G` → Toggle window grouping

### **Window Rules**
- Browsers → Workspace 1
- Code editors → Workspace 2
- Games → Workspace 4
- Media → Workspace 5
- Discord → Workspace 10

### **Workspace Organization**
1. Web browsing (Firefox/Chromium)
2. Development (VSCodium/Neovim)
3. (Free)
4. Gaming (Steam/Lutris/Heroic)
5. Media (Gimp/Kdenlive/OBS)
6. (Free)
7. (Free)
8. (Free)
9. (Free)
10. Communication (Discord/Telegram)

## Usage

### **Switching Desktop Environments**

1. Log out of your current session
2. At SDDM login screen, click the session icon (gear icon)
3. Select either:
   - **Plasma (Wayland)** - Full KDE experience
   - **Hyprland** - Tiling compositor
4. Enter password and login

### **Hyprland Basics**

**Window Management:**
- `SUPER+H/J/K/L` or Arrow keys - Move focus
- `SUPER+SHIFT+H/J/K/L` - Move windows
- `SUPER+T` - Toggle floating/tiling
- `SUPER+Space` - Toggle floating
- `SUPER+G` - Toggle window grouping
- `SUPER+ALT+Arrows` - Navigate between window groups

**Workspace Navigation:**
- `SUPER+[1-0]` - Switch workspace (uses number keys)
- `SUPER+SHIFT+[1-0]` - Move window to workspace
- `SUPER+[/]` - Previous/next workspace
- `SUPER+S` - Toggle scratchpad workspace
- `SUPER+SHIFT+S` - Move window to scratchpad

**Common Tasks:**
- `SUPER+E` - Thunar file manager
- `SUPER+N` - Discord
- `SUPER+F` - Firefox
- `SUPER+C` - VSCodium
- `SUPER+B` - Wallpaper picker
- `SUPER+K` - Show keybindings (with rofi)
- `SUPER+Escape` - System menu (logout, reboot, etc.)
- `SUPER+SHIFT+Escape` - Lock screen

### **Screenshots**
- `Print` - Capture screen to clipboard
- `SUPER+Print` - Select region to capture
- `SUPER+SHIFT+Print` - Capture region with swappy editor

### **Wallpaper**
- `SUPER+W` - Open wallpaper picker
- `SUPER+SHIFT+W` - Select from all wallpapers

## Included Software

**Essential Hyprland Packages:**
- `waybar` - Status bar
- `rofi-wayland` - Application launcher
- `mako` - Notification daemon
- `swaylock/swaylock-effects` - Lock screen
- `hyprlock` - Alternative lock screen
- `wlogout` - Logout menu
- `waypaper` - Wallpaper manager
- `swww` - Wallpaper daemon
- `grim/slurp` - Screenshot tools
- `wl-clipboard` - Clipboard management
- `hyprpicker` - Color picker

## Customization

### **Modifying Keybindings**

Edit `modules/desktop/hyprland/binds.nix`:

```nix
# Basic syntax
"$mainMod, KEY, ACTION, params"

# Example
"$mainMod, Return, Open terminal, exec, ${pkgs.kitty}/bin/kitty"
```

**Omarchy-inspired patterns used:**
- Window grouping (`SUPER+G`) - Treat multiple windows as a single unit
- Scratchpad workspace (`SUPER+S`) - Temporarily stash windows
- `SUPER+W` to close (Omarchy pattern)
- `code:10-19` for workspace keys (more portable than 1-9)
- Resize with `=`/-` keys (`SUPER+equal`, `SUPER+minus`)

### **Adding Window Rules**

Edit `modules/desktop/hyprland/windowrules.nix`:

```nix
"workspace N, class:^(appname)$"
"float, class:^(appname)$"
```

### **Changing Settings**

Edit `modules/desktop/hyprland/settings.nix` for:
- Gaps and borders
- Animations
- Blur effects
- Input devices
- Layout behavior

## Performance Notes

- **Blur enabled** but optimized (xray=true, size=5)
- **Animations** smooth but fast (3-4 speed)
- **VFR/VRR** enabled for variable refresh rate
- **Steam games** configured to disable blur/shadows

## Troubleshooting

### **Hyprland doesn't start**
- Check if enabled: `programs.hyprland.enable = true;`
- Check logs: `journalctl -u hyprland`
- Verify SDDM shows Hyprland option

### **Keybindings not working**
- Check Hyprland is actually running (not Plasma)
- Some keybindings conflict with KDE global shortcuts in Plasma
- Waybar may be blocking some keys - check its config

### **Theme colors wrong**
- Ensure Stylix is enabled in both `flake.nix` and `home.nix`
- Check `base16Scheme` matches between system and user config
- Restart Hyprland: `hyprctl reload`

### **Games performance**
- Window rules automatically disable blur for Steam
- Use `SUPER+SHIFT+F` for true fullscreen (no decorations)
- Games on workspace 4 have special optimizations

## File Locations

All configuration is declarative in `/etc/nixos/`:
- System modules: `modules/desktop/hyprland/`
- Home Manager: `home.nix` (imports hyprland module)
- Host config: `hosts/zephyr/configuration.nix`

After editing:
```bash
sudo nixos-rebuild switch --flake /etc/nixos
```

Home Manager configs apply automatically on rebuild.

## Next Steps

Would you like to:
1. **Customize keybindings** for your workflow?
2. **Add more window rules** for your apps?
3. **Configure Waybar** for custom status bar?
4. **Set up hyprpaper** for persistent wallpapers?
5. **Configure special workspaces** (scratchpad, etc.)?
