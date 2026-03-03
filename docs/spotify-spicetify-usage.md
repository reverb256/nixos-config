# Spotify + Spicetify Usage Guide

**Last Updated:** 2026-03-03
**Module:** `services.spotify-spicetify`
**Status:** Active

## Overview

This module provides automated Spicetify theming for Spotify Flatpak. Spicetify applies custom themes and extensions to Spotify, running side-by-side with SpotX (ad-blocking).

## What's Automated

- ✅ Initial Spicetify theme application
- ✅ Daily theme checks (via systemd timer)
- ✅ Automatic re-application after Spotify updates
- ✅ Version tracking to avoid unnecessary re-patching
- ✅ Backup creation before applying theme
- ✅ Auto-disable on failure with notifications

## Default Theme: Nord Dark

Your Spotify comes pre-configured with the **Dribbblish** theme in **Nord Dark** colors:
- Deep blue arctic color palette
- Professional, clean aesthetics
- Easy on the eyes for long sessions
- Excellent contrast and readability

## Quick Start

### Enable Module

Edit your NixOS configuration:

```nix
# /etc/nixos/hosts/<your-host>/configuration.nix
services.spotify-spotx.enable = true;  # Ad-blocking
services.spotify-spicetify.enable = true;  # Theming
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake /etc/nixos
```

### Launch Spotify

```bash
flatpak run com.spotify.Client
```

You should see Spotify with the Nord Dark theme applied.

## Service Status

Check if services are running:

```bash
# Check Spicetify service status
systemctl status spotify-spicetify.service

# Check timer status
systemctl status spotify-spicetify.timer

# View all Spotify-related timers
systemctl list-timers | grep spotify
```

## Manual Commands

### Check Spicetify Status

```bash
spotify-spicetify status
# Output: Spicetify: applied (version: 1.2.82.428.g0ac8be2b, theme: Dribbblish/nord-dark)
```

### Manually Apply Theme

```bash
spotify-spicetify apply
spotify-spicetify apply --verbose  # For detailed output
```

### Disable/Enable Spicetify

```bash
# Disable Spicetify (revert to stock Spotify)
spotify-spicetify disable

# Re-enable after being disabled
spotify-spicetify enable
```

### View Service Logs

```bash
# Recent logs
journalctl -u spotify-spicetify.service -n 50

# Follow logs in real-time
journalctl -u spotify-spicetify.service -f

# Today's logs
journalctl -u spotify-spicetify.service --since today
```

## Configuration

### Change Color Scheme

```nix
services.spotify-spicetify = {
  enable = true;
  theme = "Dribbblish";
  colorScheme = "catppuccin";  # Nord Dark is default
};
```

Available color schemes: `nord-dark`, `catppuccin`, `rosepine`, `dracula`

### Add Custom CSS

```nix
services.spotify-spicetify = {
  enable = true;
  customCSS = ''
    .main-card-cardContainer {
      background: rgba(59, 66, 82, 0.9);
    }
  '';
};
```

### Add Extensions

```nix
services.spotify-spicetify = {
  enable = true;
  extensions = [ "adblock" "shuffle+" "history" "skipStats" ];
};
```

### Disable Auto-Application

```nix
services.spotify-spicetify = {
  enable = true;
  autoApply = false;  # Manual only
};
```

### Change Check Interval

```nix
services.spotify-spicetify = {
  enable = true;
  checkInterval = "weekly";  # daily is default
};
```

### Change Failure Behavior

```nix
services.spotify-spicetify = {
  enable = true;
  onFailure = "notify-only";  # disable, notify-only, or ignore
};
```

## How It Works

### Automatic Theming Flow

```
1. Daily Timer (spotify-spicetify.timer) triggers
   OR
2. Flatpak Update completes (flatpak-update.service)
   ↓
3. Wait for spotx-patch.service to complete
   ↓
4. spotify-spicetify.service runs
   ↓
5. Verify SpotX is applied
   ↓
6. Get current Spotify version
   ↓
7. Compare with stored version
   ↓
8a. If versions match: Skip (already themed)
8b. If versions differ: Apply Spicetify theme
   ↓
9. Update version marker
   ↓
10. Log result to journal
```

### Service Dependencies

```
spotx-patch.service (ad-blocking)
         ↓
spotify-spicetify.service (theming)
         ↓
Spotify with both patches applied
```

## Troubleshooting

### Theme Not Applied

**Symptom:** Stock Spotify appearance

**Solution:**
```bash
# Check Spicetify status
spotify-spicetify status

# If "not applied", manually trigger
spotify-spicetify apply

# Check logs for errors
journalctl -u spotify-spicetify.service -n 50
```

### Spicetify Auto-Disabled

**Symptom:** Module is disabled, notification received

**Solution:**
```bash
# Check why it was disabled
cat /var/lib/spicetify/disabled

# Fix the issue (usually missing theme or Spotify not installed)

# Re-enable
spotify-spicetify enable
sudo systemctl start spotify-spicetify.service
```

### Spotify Update Broke Theme

**Symptom:** Spotify updated but theme not re-applied

**Solution:**
```bash
# The service should auto-detect version changes
# Manually trigger if needed:
spotify-spicetify apply

# Verify
spotify-spicetify status
```

### Theme Looks Wrong

**Symptom:** Colors incorrect, layout broken

**Solution:**
```bash
# Check color scheme is correct
spotify-spicetify apply --color-scheme nord-dark

# Try re-applying
spotify-spicetify apply --verbose

# If persistent, switch to different theme
# Edit config and rebuild
```

## Available Themes

### Dribbblish (Default)

- Modern, minimalist design
- Smooth animations
- Multiple color schemes
- Most popular Spicetify theme

### Other Themes

To use a different theme, you'll need to add it manually:

```bash
# Clone community themes
git clone https://github.com/spicetify/spicetify-themes /tmp/spicetify-themes

# Copy desired theme to config directory
sudo cp -r /tmp/spicetify-themes/Flow /etc/nixos/config/spicetify/themes/

# Update config
services.spotify-spicetify.theme = "Flow";
```

## Nord Dark Color Palette

The default Nord Dark theme uses these colors:

- **Polar Night (Backgrounds):** #2E3440, #3B4252, #434C5E, #4C566A
- **Snow Storm (Text):** #D8DEE9, #E5E9F0, #ECEFF4
- **Frost (Accents):** #8FBCBB, #88C0D0, #81A1C1, #5E81AC
- **Aurora (Alerts):** #BF616A, #D08770, #EBCB8B, #A3BE8C, #B48EAD

## Security Notes

- Spicetify scripts are downloaded from official GitHub repository
- Runs as root to access system Flatpak installation
- Only modifies Spotify Flatpak files (isolated from system)
- No user data is accessed or transmitted
- Auto-disable prevents repeated failures

## Uninstalling

To remove Spicetify and revert to stock Spotify (but keep SpotX):

```nix
services.spotify-spicetify.enable = false;
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake /etc/nixos
```

To completely remove Spotify (both SpotX and Spicetify):

```nix
services.spotify-spotx.enable = false;
services.spotify-spicetify.enable = false;
```

## Getting Help

### Logs

```bash
# All Spicetify-related logs
journalctl -u spotify-spicetify* -b

# System logs mentioning Spotify
journalctl -b | grep -i spotify
```

### Version Information

```bash
# Spotify version
flatpak info com.spotify.Client

# Spicetify status
spotify-spicetify status

# Module version
grep "spotify-spicetify" /etc/nixos/modules/desktop/spotify-spicetify.nix | head -5
```

### Testing

```bash
# Verify Spotify is themed
flatpak run com.spotify.Client
# Visual check: Nord Dark theme should be visible

# Check service is scheduled
systemctl list-timers | grep spicetify

# Force re-apply
rm /var/lib/spicetify/version
systemctl start spotify-spicetify.service
```

## References

- [Spicetify Official](https://spicetify.app/)
- [Spicetify GitHub](https://github.com/spicetify/spicetify-cli)
- [Spicetify Themes](https://github.com/spicetify/spicetify-themes)
- [Nord Theme](https://github.com/arcticicestudio/nord)
- [SpotX Integration](./spotify-spotx-usage.md)

## Module Documentation

See the design document for technical details:
- `docs/plans/2026-03-03-spotify-spicetify-design.md`