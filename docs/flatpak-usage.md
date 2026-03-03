# Flatpak + Discover + Spotube Usage Guide

## What's Been Configured

✅ **Flatpak** - Installed with automatic updates
✅ **Discover** - KDE Plasma's software center with Flatpak backend
✅ **Flathub** - Added as remote (main Flatpak app repository)
✅ **Spotube** - FOSS Spotify client (nixpkgs version)
✅ **Portal Integration** - Proper KDE integration for Flatpak apps

## Using Discover with Flatpak

### 1. Open Discover
- Right-click on your desktop → "Run Command" → type `discover`
- Or find it in your application launcher as "Discover"

### 2. Browse & Install Flatpaks
- Discover will show both **Native** (Nix) and **Flatpak** apps
- Filter by "Flatpak" to see only Flatpak apps
- Click "Install" on any app to install it

### 3. Manage Flatpaks
- **Updates**: Discover → Updates → Update All
- **Remove**: Discover → Installed → Select app → Remove

## Using Flatpak via Command Line

### Search for apps
```bash
flatpak search <app-name>
```

### Install apps
```bash
flatpak install flathub <app-id>
```

Examples:
```bash
# Spotify (if you want the official client)
flatpak install flathub com.spotify.Client

# Discord
flatpak install flathub com.discordapp.Discord

# VS Code
flatpak install flathub com.visualstudio.code

# Steam
flatpak install flathub com.valvesoftware.Steam
```

### List installed Flatpaks
```bash
flatpak list
```

### Update all Flatpaks
```bash
flatpak update
```

### Remove a Flatpak
```bash
flatpak uninstall <app-id>
```

## About Spotube

**Spotube** is a FOSS Spotify client that:
- Uses YouTube for music streaming (no Spotify Premium required)
- Has no ads
- Works with your Spotify account (for playlists, favorites, etc.)
- Uses librespot for Spotify metadata

### Launch Spotube
```bash
# From terminal
spotube

# Or find it in your application launcher
```

### First-time Setup
1. Open Spotube
2. Click "Login with Spotify"
3. Authorize the app
4. Your playlists and liked songs will sync

## Troubleshooting

### Flatpak apps can't access files
Flatpak apps are sandboxed. Grant permissions:
```bash
flatpak override --filesystem=home <app-id>
```

### Discover doesn't show Flatpaks
1. Ensure Flatpak service is running: `systemctl status flatpak-system-helper`
2. Check remotes: `flatpak remotes`
3. Restart Discover

### Portal issues (file dialogs, notifications)
Ensure portals are configured:
```bash
# Check installed portals
flatpak list | grep portal

# Reinstall if needed
nixos-rebuild switch
```

## Flatpak vs Nix Packages

| Aspect | Nix Packages | Flatpak |
|--------|-------------|---------|
| Integration | Native, declarative | Sandboxed, isolated |
| Updates | Via `nixos-rebuild` | Via Discover or CLI |
| Disk Space | Shared dependencies | Bundled dependencies |
| Security | Depends on package | Sandboxed |
| GUI Apps | Limited selection | Wide selection (Flathub) |

### When to use which:
- **Nix packages**: CLI tools, system utilities, libraries
- **Flatpak**: GUI applications, proprietary apps, games

## Useful Flatpaks to Consider

### Communication
- `com.discordapp.Discord` - Discord
- `org.telegram.desktop` - Telegram
- `com.slack.Slack` - Slack

### Development
- `com.visualstudio.code` - VS Code
- `org.gnome.Builder` - GNOME Builder IDE
- `com.jetbrains.IntelliJ-IDEA-Community` - IntelliJ IDEA

### Productivity
- `org.libreoffice.LibreOffice` - LibreOffice
- `org.gimp.GIMP` - GIMP
- `org.inkscape.Inkscape` - Inkscape

### Gaming
- `com.valvesoftware.Steam` - Steam
- `com.valvesoftware.Steam.CompatibilityTool.Proton-GE` - Proton GE

### Utilities
- `com.bitwarden.desktop` - Bitwarden
- `org.keepassxc.KeePassXC` - KeePassXC
- `us.zoom.Zoom` - Zoom

## Automatic Updates

Flatpak apps are configured to auto-update weekly. To manually update:

```bash
# Update all Flatpaks
flatpak update

# Check for updates without installing
flatpak update --appstream
```

## Resources

- [Flathub Website](https://flathub.org)
- [Flatpak Documentation](https://docs.flatpak.org)
- [Spotube GitHub](https://github.com/KRTirtho/spotube)
