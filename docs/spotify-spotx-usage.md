# Spotify + SpotX Usage Guide (Flatpak)

**Last Updated:** 2026-03-07
**Module:** `services.spotify-spotx`
**Status:** Active
**Spotify Source:** Flatpak (Flathub)

## Overview

This module provides automated SpotX-Bash patching for Spotify Flatpak. SpotX removes ads, unlocks premium features, and enables experimental features in the Spotify desktop client.

## What's Automated

- ✅ Automatic Spotify Flatpak installation (optional)
- ✅ Initial SpotX patch application
- ✅ Daily patch checks (via systemd timer)
- ✅ Automatic re-patching after Flatpak updates
- ✅ Version tracking to avoid unnecessary re-patching
- ✅ Integration with system Flatpak update service

## Quick Start

### 1. Enable in Configuration

```nix
# /etc/nixos/hosts/<your-host>/configuration.nix
services.spotify-spotx = {
  enable = true;
  forceX11 = true;  # Recommended for Wayland: fixes close button
};
```

### 2. Rebuild

```bash
sudo nixos-rebuild switch --flake /etc/nixos
```

### 3. Launch Spotify

```bash
# Via CLI tool
spotify-spotx launch

# Or directly with Flatpak
flatpak run com.spotify.Client
```

## Service Status

Check if services are running:

```bash
# Check patch service status
systemctl status spotx-patch.service

# Check timer status
systemctl status spotx-patch.timer

# Check Flatpak integration
systemctl status flatpak-update.service

# View all SpotX timers
systemctl list-timers | grep spotx
```

## CLI Commands

The `spotify-spotx` command provides all management functions:

```bash
# Check status
spotify-spotx status

# Apply patch manually
spotify-spotx patch

# Install Spotify Flatpak
spotify-spotx install

# Launch Spotify
spotify-spotx launch

# Clear cache (fixes ads showing)
spotify-spotx clear-cache
```

### Status Output Example

```
$ spotify-spotx status
Spotify Flatpak: installed (1.2.32.123.g0abcdef)
Installation path: /var/lib/flatpak/app/com.spotify.Client/x86_64/stable/active/install
SpotX: applied (version: 1.2.32.123.g0abcdef)
```

## How It Works

### Automatic Patching Flow

```
1. Daily Timer (spotx-patch.timer) triggers
   OR
2. Flatpak Update completes (flatpak-update.service)
   ↓
3. spotx-patch.service runs
   ↓
4. Checks if Spotify Flatpak is installed
   ↓
5. Gets current Spotify version (flatpak info)
   ↓
6. Compares with patched version (stored in /var/lib/spotx/.spotx_patched)
   ↓
7a. If versions match: Skip patching (already patched)
7b. If versions differ: Apply SpotX patch
   ↓
8. Update version marker
   ↓
9. Log result to journal
```

### Flatpak Update Integration

When you run `flatpak update` or the weekly `flatpak-update.service` runs:

1. Flatpak updates all packages (including Spotify if available)
2. `spotx-patch.service` automatically triggers (via `After=` dependency)
3. SpotX patch is re-applied to the updated Spotify
4. No manual intervention required

## State Files

The module maintains state in `/var/lib/spotx/`:

```
/var/lib/spotx/
├── backups/           # Backup directory (for future use)
└── .spotx_patched     # Version marker (contains Spotify version)
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable the module |
| `autoInstall` | bool | true | Auto-install Spotify Flatpak |
| `autoPatch` | bool | true | Auto-apply patch on updates |
| `patchCheckInterval` | str | "daily" | How often to check (systemd format) |
| `forceX11` | bool | false | Force X11 backend (Wayland CSD fix) |
| `clearCacheOnPatch` | bool | true | Clear cache after patching |

### Example Configurations

**Disable auto-installation:**
```nix
services.spotify-spotx = {
  enable = true;
  autoInstall = false;  # Install manually with: flatpak install flathub com.spotify.Client
};
```

**Change patch check interval:**
```nix
services.spotify-spotx = {
  enable = true;
  patchCheckInterval = "hourly";  # Check every hour
};
```

**Disable auto-patching (manual only):**
```nix
services.spotify-spotx = {
  enable = true;
  autoPatch = false;  # Run: spotify-spotx patch manually
};
```

## Troubleshooting

### Spotify Not Installed

**Symptom:** `spotify-spotx status` shows "not installed"

**Solution:**
```bash
# Install manually
spotify-spotx install

# Or via Flatpak directly
flatpak install flathub com.spotify.Client
```

### Spotify Not Patched

**Symptom:** Ads still showing

**Solution:**
```bash
# Check status
spotify-spotx status

# Manually apply patch
spotify-spotx patch

# Check logs for errors
journalctl -u spotx-patch.service -n 50
```

### Patch Service Failing

**Symptom:** `spotx-patch.service` shows as failed

**Solution:**
```bash
# View error logs
journalctl -xeu spotx-patch.service

# Common issues:
# - No internet connection (SpotX downloads from GitHub)
# - Spotify not installed
# - SpotX script incompatible with new Spotify version
```

### Wayland Close Button Not Working

**Symptom:** Close button doesn't work on Wayland

**Solution:**
```nix
services.spotify-spotx = {
  enable = true;
  forceX11 = true;  # Forces XWayland backend
};
```

Then rebuild and re-patch:
```bash
sudo nixos-rebuild switch --flake /etc/nixos
spotify-spotx patch
```

### View Logs

```bash
# Recent logs
journalctl -u spotx-patch.service -n 50

# Follow logs in real-time
journalctl -u spotx-patch.service -f

# Today's logs
journalctl -u spotx-patch.service --since today

# Logs from last run
journalctl -u spotx-patch.service --since "1 hour ago"
```

## Launching Spotify

### Command Line

```bash
# Via the CLI tool
spotify-spotx launch

# Directly with Flatpak
flatpak run com.spotify.Client

# With XWayland (if forceX11 is enabled)
flatpak run --env=OZONE_PLATFORM=x11 com.spotify.Client
```

### Desktop Menu

Look for "Spotify" in your application launcher (KDE menu, etc.)

### First Launch

On first launch after patching:
1. Spotify may take longer to start (extracting patched files)
2. You might see a brief "Installing update" message
3. Subsequent launches will be normal speed

## What SpotX Changes

SpotX-Bash modifies Spotify to:
- ✅ Remove audio and display ads
- ✅ Unlock premium features (on-demand playback, unlimited skips)
- ✅ Enable experimental features
- ✅ Remove upgrade prompts
- ✅ Hide podcast/episode sections (optional)

**Note:** SpotX does NOT enable offline downloads or Spotify Connect (these require valid premium account).

## Uninstalling

### Disable Module Only

```nix
services.spotify-spotx.enable = false;
```

```bash
sudo nixos-rebuild switch --flake /etc/nixos
```

### Completely Remove Spotify

```bash
# Uninstall Spotify Flatpak
flatpak uninstall com.spotify.Client

# Remove state files
sudo rm -rf /var/lib/spotx

# Disable and remove services
sudo systemctl disable spotx-patch.service spotx-patch.timer
```

## Security Notes

- SpotX-Bash script is downloaded from official GitHub repository
- Script is executed in controlled systemd environment
- Only modifies Spotify Flatpak files (isolated from system)
- Runs as root to access system Flatpak installation
- No user data is accessed or transmitted

## Comparison: Nixpkgs vs Flatpak

| Aspect | Nixpkgs (old) | Flatpak (current) |
|--------|--------------|-------------------|
| Updates | `nixos-rebuild` | `flatpak update` |
| Source | `pkgs.spotify` | Flathub |
| Path | `/nix/store/...` | `/var/lib/flatpak/...` |
| Patching | Copy to `/var/lib/spotify-spotx/` | Direct in Flatpak dir |
| Command | `spotify` | `flatpak run com.spotify.Client` |
| Wrapper | Yes (symlinkJoin) | No (native Flatpak) |

## Getting Help

### Version Information

```bash
# Spotify version
flatpak info com.spotify.Client

# SpotX status
spotify-spotx status

# Check if Flatpak is working
flatpak list | grep spotify
```

### Testing

```bash
# Verify Spotify is patched
spotify-spotx launch
# Play a song → should be no ads

# Check service is scheduled
systemctl list-timers | grep spotx

# Force re-patch
sudo rm /var/lib/spotx/.spotx_patched
sudo systemctl start spotx-patch.service
```

## Spicetify Integration

This module works alongside `services.spotify-spicetify` for complete Spotify customization:

- **SpotX** (this module): Removes ads, unlocks premium features
- **Spicetify**: Applies custom themes, extensions, and UI enhancements

Both modules can run side-by-side:
```nix
services.spotify-spotx.enable = true;    # Ad-blocking
services.spotify-spicetify.enable = true; # Theming
```

See [Spotify + Spicetify Usage Guide](./spotify-spicetify-usage.md) for complete theming documentation.

## References

- [SpotX Official Website](https://spotx-official.github.io/)
- [SpotX GitHub Repository](https://github.com/SpotX-Official/SpotX-Bash)
- [Spotify Flatpak on Flathub](https://flathub.org/apps/com.spotify.Client)
- [Flatpak Documentation](https://docs.flatpak.org)
