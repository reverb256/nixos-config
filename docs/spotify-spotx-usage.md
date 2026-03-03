# Spotify + SpotX Usage Guide

**Last Updated:** 2026-03-02
**Module:** `services.spotify-spotx`
**Status:** Active

## Overview

This module provides automated SpotX-Bash patching for Spotify Flatpak. SpotX removes ads, unlocks premium features, and enables experimental features in the Spotify desktop client.

## What's Automated

- ✅ Initial Spotify Flatpak installation and patching
- ✅ Daily patch checks (via systemd timer)
- ✅ Automatic re-patching after Flatpak updates
- ✅ Version tracking to avoid unnecessary re-patching
- ✅ Backup creation before patching

## Service Status

Check if services are running:

```bash
# Check patch service status
systemctl status spotx-patch.service

# Check timer status
systemctl status spotx-patch.timer

# Check Flatpak integration
systemctl status flatpak-update-after.service

# View all SpotX timers
systemctl list-timers | grep spotx
```

## Manual Commands

### Check SpotX Status

```bash
spotify-spotx status
# Output: SpotX: applied (version: 1.2.82.428.g0ac8be2b)
```

### Manually Apply Patch

```bash
sudo systemctl start spotx-patch.service
```

### View Service Logs

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

## How It Works

### Automatic Patching Flow

```
1. Daily Timer (spotx-patch.timer) triggers
   OR
2. Flatpak Update completes (flatpak-update.service)
   ↓
3. spotx-patch.service runs
   ↓
4. Gets current Spotify version
   ↓
5. Compares with patched version (stored in /var/lib/spotx/...)
   ↓
6a. If versions match: Skip patching (already patched)
6b. If versions differ: Apply SpotX patch
   ↓
7. Update version marker
   ↓
8. Log result to journal
```

### Flatpak Update Integration

When you run `flatpak update` or the weekly `flatpak-update.service` runs:

1. Flatpak updates all packages (including Spotify if available)
2. `flatpak-update-after.service` automatically triggers
3. SpotX patch is re-applied to the updated Spotify
4. No manual intervention required

## State Files

The module maintains state in `/var/lib/spotx/`:

```
/var/lib/spotx/
├── backups/           # Backup files created before patching
└── (version marker stored in Spotify directory)
```

The version marker is stored at:
```
/var/lib/flatpak/app/com.spotify.Client/.../Apps/.spotx_patched
```

## Troubleshooting

### Spotify Not Patched

**Symptom:** Ads still showing

**Solution:**
```bash
# Check SpotX status
spotify-spotx status

# If "not applied", manually trigger patch
sudo systemctl start spotx-patch.service

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
# - Spotify not installed (run initial setup)
# - Outdated SpotX script (automatic retry with exponential backoff)
```

### Spotify Update Broke Patch

**Symptom:** Spotify updated but patch not re-applied

**Solution:**
```bash
# The service should auto-detect version changes
# Manually trigger if needed:
sudo systemctl start spotx-patch.service

# Verify
spotify-spotx status
```

### Initial Setup Not Run

**Symptom:** Module enabled but Spotify not installed

**Solution:**
```bash
# Run initial setup manually
sudo bash /etc/spotx/setup-spotify.sh

# Or trigger the service
sudo systemctl start spotx-patch.service
```

## Configuration

### Disable Auto-Patching

Edit your NixOS configuration:

```nix
# /etc/nixos/hosts/<your-host>/configuration.nix
services.spotify-spotx = {
  enable = true;
  autoPatch = false;  # Disable automatic timer
};
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake /etc/nixos
```

### Change Patch Check Interval

Edit your NixOS configuration:

```nix
services.spotify-spotx = {
  enable = true;
  patchCheckInterval = "hourly";  # Or "weekly", "daily", etc.
};
```

See `man systemd.time` for valid time formats.

## Launching Spotify

### Command Line

```bash
flatpak run com.spotify.Client
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

To remove SpotX and revert to stock Spotify:

```nix
# /etc/nixos/hosts/<your-host>/configuration.nix
services.spotify-spotx.enable = false;
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake /etc/nixos
```

To completely remove Spotify:
```bash
# Uninstall Spotify Flatpak
flatpak uninstall com.spotify.Client

# Remove state files
sudo rm -rf /var/lib/spotx
```

## Security Notes

- SpotX-Bash script is downloaded from official GitHub repository
- Script is executed in controlled systemd environment
- Only modifies Spotify Flatpak files (isolated from system)
- Runs as root to access system Flatpak installation
- No user data is accessed or transmitted

## Getting Help

### Logs

```bash
# All SpotX-related logs
journalctl -u spotx-patch* -b

# Flatpak update integration logs
journalctl -u flatpak-update-after.service -b

# System logs mentioning Spotify
journalctl -b | grep -i spotify
```

### Version Information

```bash
# Spotify version
flatpak info com.spotify.Client

# SpotX status
spotify-spotx status

# Module version
grep "spotx" /etc/nixos/modules/desktop/spotify-spotx.nix | head -5
```

### Testing

```bash
# Verify Spotify is patched
flatpak run com.spotify.Client
# Play a song → should be no ads

# Check service is scheduled
systemctl list-timers | grep spotx

# Force re-patch
sudo rm /var/lib/flatpak/app/com.spotify.Client/*/files/extra/share/spotify/Apps/.spotx_patched
sudo systemctl start spotx-patch.service
```

## References

- [SpotX Official Website](https://spotx-official.github.io/)
- [SpotX GitHub Repository](https://github.com/SpotX-Official/SpotX-Bash)
- [Spotify Flatpak on Flathub](https://flathub.org/apps/com.spotify.Client)
- [NixOS Flatpak Integration](/etc/nixos/docs/spotify-spotx-usage.md)

## Module Documentation

See the implementation plan for technical details:
- `/etc/nixos/docs/plans/2026-03-02-spotify-spotx-cicd.md`
- `/etc/nixos/docs/plans/2026-03-02-spotify-spotx-cicd-design.md`
