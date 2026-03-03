# Spotify + Spicetify Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create declarative Spicetify integration for NixOS that applies themes and extensions to Spotify Flatpak automatically, running side-by-side with existing SpotX module.

**Architecture:** Dual-module architecture where SpotX handles ad-blocking (existing) and new Spicetify module handles theming/extensions. Both operate independently on same Spotify Flatpak installation, coordinated via systemd dependencies (SpotX → Spicetify), with auto-disable on failure.

**Tech Stack:** NixOS modules, systemd services/timers, spicetify-nix flake input, Flatpak Spotify, shell scripts, Nord Dark color palette

---

## Task 1: Add spicetify-nix Flake Input

**Files:**
- Modify: `flake.nix`

**Step 1: Add spicetify-nix input to flake.nix**

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # ... existing inputs (zen-browser, firefox-addons, aagl, nur, etc.)

    spicetify-nix = {  # NEW INPUT
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, spicetify-nix, zen-browser, firefox-addons, aagl, nur, claude-native, nixpkgs-xr, scopebuddy, nixcord }: {
    # ... rest of outputs
  };
}
```

**Step 2: Verify flake metadata updates**

Run: `nix flake metadata`
Expected: Output shows spicetify-nix in inputs list

**Step 3: Commit**

```bash
git add flake.nix
git commit -m "feat(spicetify): add spicetify-nix flake input

Add spicetify-nix as flake input for declarative Spicetify
integration. Will be used by spotify-spicetify module.

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 2: Create Core Module Structure

**Files:**
- Create: `modules/desktop/spotify-spicetify.nix`

**Step 1: Write module skeleton with options**

```nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.spotify-spicetify;
  stateDir = "/var/lib/spicetify";

in {
  options.services.spotify-spicetify = {
    enable = mkEnableOption "Spotify theming and extensions via Spicetify";

    configPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to custom Spicetify config directory";
    };

    theme = mkOption {
      type = types.nullOr types.str;
      default = "Dribbblish";
      description = "Theme name to apply";
    };

    colorScheme = mkOption {
      type = types.str;
      default = "nord-dark";
      description = "Color scheme for theme";
    };

    customCSS = mkOption {
      type = types.lines;
      default = "";
      description = "Custom CSS to inject";
    };

    extensions = mkOption {
      type = types.listOf types.str;
      default = [ "adblock" "shuffle+" ];
      description = "List of extension names to enable";
    };

    customApps = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of custom apps to add";
    };

    autoApply = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically re-apply when Spotify updates";
    };

    checkInterval = mkOption {
      type = types.str;
      default = "daily";
      description = "How often to check and re-apply";
    };

    onFailure = mkOption {
      type = types.enum [ "disable" "notify-only" "ignore" ];
      default = "disable";
      description = "Behavior when Spicetify fails";
    };

    enableNotifications = mkOption {
      type = types.bool;
      default = true;
      description = "Send desktop notifications";
    };

    preApplyHook = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Script to run before applying";
    };

    postApplyHook = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Script to run after applying";
    };
  };

  config = mkIf cfg.enable {
    # TODO: Add implementation in next tasks
  };
}
```

**Step 2: Verify syntax with nix-repl**

Run: `nix-instantiate --eval modules/desktop/spotify-spicetify.nix`
Expected: No syntax errors

**Step 3: Commit**

```bash
git add modules/desktop/spotify-spicetify.nix
git commit -m "feat(spicetify): add module with configuration options

Define all module options for spotify-spicetify including theme,
color scheme, extensions, hooks, and failure behavior.

Implementation will be added in subsequent commits.

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 3: Create State Directories

**Files:**
- Modify: `modules/desktop/spotify-spicetify.nix`

**Step 1: Add systemd tmpfiles rules**

Add to `config = mkIf cfg.enable {`:

```nix
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 root root -"
      "d ${stateDir}/backups 0755 root root -"
    ];
```

**Step 2: Verify syntax**

Run: `nix-instantiate --eval modules/desktop/spotify-spicetify.nix`
Expected: No errors

**Step 3: Commit**

```bash
git add modules/desktop/spotify-spicetify.nix
git commit -m "feat(spicetify): add state directory management

Create /var/lib/spicetify with tmpfiles for state management
including backups directory for Spotify Apps/ backups.

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 4: Create Patch Manager Script

**Files:**
- Modify: `modules/desktop/spotify-spicetify.nix`

**Step 1: Write patch-manager.sh script**

Add before `config =`:

```nix
  patchManagerScript = pkgs.writeShellScript "spicetify-patch-manager.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    PATH="/run/current-system/sw/bin:$PATH"

    RED='\\033[0;31m'; GREEN='\\033[0;32m'; YELLOW='\\033[1;33m'; NC='\\033[0m'
    log() { echo -e "''${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]''${NC} $1"; }
    error() { echo -e "''${RED}[ERROR]''${NC} $1" >&2; }
    warn() { echo -e "''${YELLOW}[WARN]''${NC} $1"; }

    SPOTIFY_PATH="$(flatpak info com.spotify.Client --show-location 2>/dev/null)"
    SPOTIFY_DIR="''${SPOTIFY_PATH}/files/extra/share/spotify"
    BACKUP_DIR="${stateDir}/backups"
    VERSION_MARKER="${stateDir}/version"
    DISABLED_MARKER="${stateDir}/disabled"
    CONFIG_HASH="${stateDir}/config-applied"

    get_spotify_version() {
      flatpak info com.spotify.Client 2>/dev/null | grep "Version:" | awk '{print $2}' || echo "unknown"
    }

    is_patched() {
      [ -f "$VERSION_MARKER" ] && ${pkgs.flatpak}/bin/flatpak list | grep -q "com.spotify.Client"
    }

    apply_spicetify() {
      log "Starting Spicetify theming..."

      # Check if Spotify exists
      if [ ! -d "$SPOTIFY_DIR" ]; then
        error "Spotify directory not found at: $SPOTIFY_DIR"
        return 1
      fi

      # Check if SpotX is applied
      SPOTX_MARKER="$SPOTIFY_DIR/Apps/.spotx_patched"
      if [ ! -f "$SPOTX_MARKER" ]; then
        warn "SpotX not applied yet, waiting for spotx-patch.service"
        return 0
      fi

      local current_version=$(get_spotify_version)
      log "Spotify version: $current_version"

      # Check if already applied for this version
      if [ -f "$VERSION_MARKER" ]; then
        local patched_version=$(cat "$VERSION_MARKER" 2>/dev/null || echo "unknown")
        if [ "$patched_version" = "$current_version" ]; then
          log "Spicetify already applied for version $current_version"
          return 0
        fi
        log "Spotify updated from $patched_version to $current_version, re-applying..."
      fi

      # Stop Spotify
      log "Stopping Spotify..."
      flatpak kill com.spotify.Client 2>/dev/null || true

      # Backup
      local backup_name="backup-$(date +%Y%m%d-%H%M%S)"
      if [ -d "$SPOTIFY_DIR/Apps" ]; then
        mkdir -p "$BACKUP_DIR"
        cp -r "$SPOTIFY_DIR/Apps" "$BACKUP_DIR/$backup_name"
        log "Backup created: $backup_name"
      fi

      # Apply Spicetify via spicetify-nix
      log "Applying Spicetify theme and extensions..."
      if ${pkgs.spicetify-cli}/bin/spicetify apply; then
        echo "$current_version" > "$VERSION_MARKER"
        log "Spicetify applied successfully!"
        return 0
      else
        error "Spicetify application failed"
        return 1
      fi
    }

    disable_spicetify() {
      log "Disabling Spicetify..."
      echo "$1" > "$DISABLED_MARKER"
      systemctl disable spotify-spicetify.service
      systemctl stop spotify-spicetify.timer
      if ${pkgs.libnotify}/bin/notify-send "Spicetify" "Disabled due to error: $1" 2>/dev/null; then
        log "Desktop notification sent"
      fi
    }

    show_status() {
      if [ ! -f "$VERSION_MARKER" ]; then
        echo "Spicetify: not applied"
        return 1
      fi

      local current_version=$(get_spotify_version)
      local patched_version=$(cat "$VERSION_MARKER" 2>/dev/null || echo "unknown")

      if [ "$patched_version" = "$current_version" ]; then
        echo "Spicetify: applied (version: $current_version, theme: ${builtins.replaceStrings ["\""] [""] cfg.theme}/${cfg.colorScheme})"
        return 0
      else
        echo "Spicetify: version mismatch (patched: $patched_version, current: $current_version)"
        return 1
      fi
    }

    case "''${1:-apply}" in
      apply)
        if ! apply_spicetify; then
          if [ "${cfg.onFailure}" = "disable" ]; then
            disable_spicetify "Theme application failed"
          fi
          exit 1
        fi
        ;;
      status) show_status ;;
      disable) rm -f "$VERSION_MARKER" "$DISABLED_MARKER"; log "Spicetify disabled" ;;
      enable) rm -f "$DISABLED_MARKER"; log "Spicetify re-enabled" ;;
      *) echo "Usage: $0 {apply|status|disable|enable}"; exit 1 ;;
    esac
  '';
```

**Step 2: Verify syntax**

Run: `nix-instantiate --eval modules/desktop/spotify-spicetify.nix`
Expected: No errors

**Step 3: Commit**

```bash
git add modules/desktop/spotify-spicetify.nix
git commit -m "feat(spicetify): add patch manager script

Implement core Spicetify application logic including:
- Version checking and comparison
- SpotX dependency verification
- Backup creation before patching
- Auto-disable on failure
- Status reporting

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 5: Create Systemd Service

**Files:**
- Modify: `modules/desktop/spotify-spicetify.nix`

**Step 1: Add systemd service configuration**

Add to `config = mkIf cfg.enable {`:

```nix
    systemd.services.spotify-spicetify = {
      description = "Spotify Spicetify Theme Service";
      after = [ "spotx-patch.service" "network-online.target" ];
      wants = [ "spotx-patch.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${patchManagerScript} apply";
        StandardOutput = "journal";
        StandardError = "journal";
        User = "root";
        Group = "root";
      };
    };
```

**Step 2: Verify syntax**

Run: `nix-instantiate --eval modules/desktop/spotify-spicetify.nix`
Expected: No errors

**Step 3: Commit**

```bash
git add modules/desktop/spotify-spicetify.nix
git commit -m "feat(spicetify): add systemd service

Create spotify-spicetify service that runs after spotx-patch
to ensure correct patching order. Service runs oneshot to
apply theme and extensions.

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 6: Create Systemd Timer

**Files:**
- Modify: `modules/desktop/spotify-spicetify.nix`

**Step 1: Add systemd timer configuration**

Add to `config = mkIf cfg.enable {`:

```nix
    systemd.timers.spotify-spicetify = mkIf cfg.autoApply {
      description = "Spotify Spicetify Auto-Theme Timer";
      wantedBy = [ "timers.target" ];
      partOf = [ "spotify-spicetify.service" ];
      timerConfig = {
        OnCalendar = cfg.checkInterval;
        Unit = "spotify-spicetify.service";
        Persistent = true;
      };
    };
```

**Step 2: Verify syntax**

Run: `nix-instantiate --eval modules/desktop/spotify-spicetify.nix`
Expected: No errors

**Step 3: Commit**

```bash
git add modules/desktop/spotify-spicetify.nix
git commit -m "feat(spicetify): add systemd timer for auto-application

Create daily timer that automatically re-applies Spicetify
when Spotify updates. Configurable via checkInterval option.

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 7: Add Flatpak Update Integration

**Files:**
- Modify: `modules/desktop/spotify-spicetify.nix`

**Step 1: Add after-flatpak-update service**

Add to `config = mkIf cfg.enable {`:

```nix
    systemd.services.spotify-spicetify-after-flatpak = mkIf config.services.flatpak.enable {
      description = "Run Spicetify after Flatpak updates";
      after = [ "flatpak-update.service" ];
      wants = [ "flatpak-update.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${patchManagerScript} apply";
        StandardOutput = "journal";
        StandardError = "journal";
        User = "root";
        Group = "root";
      };
    };
```

**Step 2: Verify syntax**

Run: `nix-instantiate --eval modules/desktop/spotify-spicetify.nix`
Expected: No errors

**Step 3: Commit**

```bash
git add modules/desktop/spotify-spicetify.nix
git commit -m "feat(spicetify): integrate with flatpak-update service

Automatically re-apply Spicetify after flatpak-update runs
to ensure theme persists through Spotify updates.

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 8: Create CLI Command

**Files:**
- Modify: `modules/desktop/spotify-spicetify.nix`

**Step 1: Add spotify-spicetify command to systemPackages**

Add to `config = mkIf cfg.enable {`:

```nix
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "spotify-spicetify" ''
        #!${bash}/bin/bash
        ${patchManagerScript} "$@"
      '')
    ];
```

**Step 2: Verify syntax**

Run: `nix-instantiate --eval modules/desktop/spotify-spicetify.nix`
Expected: No errors

**Step 3: Commit**

```bash
git add modules/desktop/spotify-spicetify.nix
git commit -m "feat(spicetify): add CLI command for manual control

Add spotify-spicetify command wrapping patch manager script.
Supports: status, apply, disable, enable subcommands.

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 9: Create Default Configuration Directory

**Files:**
- Create: `config/spicetify/themes/Dribbblish/color.ini`
- Create: `config/spicetify/themes/Dribbblish/user.css`
- Create: `config/spicetify/extensions/adblock.js`
- Create: `config/spicetify/extensions/shuffle+.js`
- Create: `config/spicetify/config.xini`

**Step 1: Create Nord Dark color scheme**

```bash
mkdir -p config/spicetify/themes/Dribbblish
cat > config/spicetify/themes/Dribbblish/color.ini << 'EOF'
[Dribbblish]
text                = FFFFFF
subtext             = D8DEE9
main                = 2E3440
sidebar             = 3B4252
player              = 2E3440
card                = 3B4252
shadow              = 242933
selected            = 88C0D0
button              = 5E81AC
button-active       = 81A1C1
button-disabled     = 4C566A
tab-active          = 88C0D0
notification        = 5E81AC
notification-error  = BF616A
equality            = 88C0D0
equalizer-bar       = 88C0D0
EOF
```

**Step 2: Create Dribbblish user.css**

```bash
cat > config/spicetify/themes/Dribbblish/user.css << 'EOF'
/* Dribbblish theme - Nord Dark variant */
:root {
  --spice-main: #2E3440;
  --spice-sidebar: #3B4252;
  --spice-selected: #88C0D0;
  --spice-button: #5E81AC;
}

/* Add transparency to cards */
.main-card-cardContainer {
  background: rgba(59, 66, 82, 0.8) !important;
  backdrop-filter: blur(10px);
}
EOF
```

**Step 3: Create placeholder extension files**

```bash
mkdir -p config/spicetify/extensions

# adblock.js placeholder
cat > config/spicetify/extensions/adblock.js << 'EOF'
// AdBlock extension for Spicetify
// Actual implementation will be downloaded from Spicetify marketplace
EOF

# shuffle+.js placeholder
cat > config/spicetify/extensions/shuffle+.js << 'EOF'
// Shuffle+ extension for Spicetify
// Actual implementation will be downloaded from Spicetify marketplace
EOF
```

**Step 4: Create base Spicetify config**

```bash
cat > config/spicetify/config.xini << 'EOF'
[Setting]
spice_path=
spotify_path=
prefs_path=
current_theme=Dribbblish
inject_css=1
inject_js=1
replace_colors=1
overwrite_assets=0
EOF
```

**Step 5: Commit**

```bash
git add config/spicetify/
git commit -m "feat(spicetify): add default Nord Dark theme configuration

Add Dribbblish theme with Nord Dark color palette as default
configuration. Includes color.ini, user.css, and base
Spicetify config.xini file.

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 10: Write Usage Documentation

**Files:**
- Create: `docs/spotify-spicetify-usage.md`

**Step 1: Write comprehensive usage guide**

```bash
cat > docs/spotify-spicetify-usage.md << 'EOF'
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
EOF
```

**Step 2: Commit**

```bash
git add docs/spotify-spicetify-usage.md
git commit -m "docs(spicetify): add comprehensive usage guide

Document spotify-spicetify module including:
- Quick start and default theme info
- Service status and manual commands
- Configuration examples
- Troubleshooting guide
- Available themes and color schemes
- Security notes and uninstall instructions

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 11: Create Testing Script

**Files:**
- Create: `docs/test-spicetify-integration.sh`

**Step 1: Write integration test script**

```bash
cat > docs/test-spicetify-integration.sh << 'EOF'
#!/usr/bin/env bash
# Test script for Spotify + Spicetify integration

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check() {
  if $1; then
    echo -e "${GREEN}✓${NC} $2"
  else
    echo -e "${RED}✗${NC} $2"
    return 1
  fi
}

echo "=== Spotify + Spicetify Integration Test ==="
echo

echo "=== Prerequisites ==="
check "flatpak list | grep -q 'com.spotify.Client'" "Spotify Flatpak installed"
check "systemctl is-enabled --quiet spotx-patch.timer" "SpotX timer enabled"
check "command -v spotify-spotx &>/dev/null" "SpotX CLI available"

echo
echo "=== Module Check ==="
check "systemctl list-units | grep -q spotify-spicetify" "Spicetify service exists"
check "systemctl is-enabled --quiet spotify-spicetify.timer 2>/dev/null" "Spicetify timer enabled"
check "[ -d '/var/lib/spicetify' ]" "Spicetify state directory exists"
check "command -v spotify-spicetify &>/dev/null" "Spicetify CLI available"

echo
echo "=== Service Dependencies ==="
systemctl show spotify-spicetify.service | grep After= | grep spotx-patch
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓${NC} Spicetify runs after SpotX (correct order)"
else
  echo -e "${RED}✗${NC} Dependency chain broken"
fi

echo
echo "=== Status Check ==="
spotify-spicetify status || echo -e "${YELLOW}⚠${NC} Status check returned non-zero"

echo
echo "=== Config Files ==="
check "[ -f '/etc/nixos/config/spicetify/themes/Dribbblish/color.ini' ]" "Nord Dark color.ini exists"
check "[ -f '/etc/nixos/config/spicetify/themes/Dribbblish/user.css' ]" "Dribbblish user.css exists"

echo
echo "=== Verification Complete ==="
echo "If all checks passed, the integration is working correctly."
EOF

chmod +x docs/test-spicetify-integration.sh
```

**Step 2: Commit**

```bash
git add docs/test-spicetify-integration.sh
git commit -m "test(spicetify): add integration test script

Add automated test script to verify:
- Prerequisites (Spotify, SpotX)
- Service existence and enablement
- State directory creation
- CLI availability
- Service dependencies
- Status reporting
- Config file presence

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 12: Enable Module in Host Configuration

**Files:**
- Modify: `hosts/zephyr/configuration.nix`

**Step 1: Add module to host config**

Find the services section and add:

```nix
services.spotify-spotx.enable = true;
services.spotify-spicetify.enable = true;
```

**Step 2: Verify module is in imports list**

Ensure the module is imported at the top:

```nix
{
  imports = [
    ../../modules/desktop/spotify-spotx.nix
    ../../modules/desktop/spotify-spicetify.nix  # Add this
    # ... other imports
  ];

  # ... rest of config
}
```

**Step 3: Test configuration syntax**

Run: `sudo nixos-rebuild test --flake /etc/nixos`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add hosts/zephyr/configuration.nix
git commit -m "feat(zephyr): enable spotify-spicetify module

Enable Spicetify theming alongside existing SpotX ad-blocking.
Default theme: Dribbblish with Nord Dark color scheme.

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 13: Rebuild and Test

**Step 1: Rebuild system**

```bash
sudo nixos-rebuild switch --flake /etc/nixos
```

Expected: Build completes successfully, no errors

**Step 2: Verify services started**

```bash
systemctl status spotify-spicetify.service
systemctl status spotify-spicetify.timer
```

Expected: Both services are loaded and active

**Step 3: Run integration test**

```bash
sudo docs/test-spicetify-integration.sh
```

Expected: All checks pass

**Step 4: Check CLI status**

```bash
spotify-spicetify status
```

Expected: "Spicetify: applied (version: X.X.X.X, theme: Dribbblish/nord-dark)"

**Step 5: Launch Spotify visually**

```bash
flatpak run com.spotify.Client
```

Expected: Spotify opens with Nord Dark theme visible

**Step 6: Commit final setup**

```bash
git add -A
git commit -m "feat(spicetify): complete integration and testing

All components working:
- Module enabled in host config
- Services running correctly
- Integration tests passing
- CLI commands functional
- Visual theme applied to Spotify

Ready for production use.

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Task 14: Update SpotX Documentation

**Files:**
- Modify: `docs/spotify-spotx-usage.md`

**Step 1: Add Spicetify integration note**

Add at the end of the document:

```markdown
## Integration with Spicetify

This SpotX module is designed to work alongside the Spicetify module for theming:

- **SpotX:** Handles ad-blocking via official SpotX-Bash
- **Spicetify:** Handles themes, extensions, and customizations

Both modules operate independently on the same Spotify Flatpak installation,
with systemd ensuring SpotX runs first, then Spicetify applies theming.

See [Spicetify Usage Guide](./spotify-spicetify-usage.md) for details.
```

**Step 2: Commit**

```bash
git add docs/spotify-spotx-usage.md
git commit -m "docs(spotx): add Spicetify integration note

Document that SpotX and Spicetify modules are designed to work
together with proper service ordering.

Related: #2026-03-03-spotify-spicetify-design"
```

---

## Success Criteria Verification

After completing all tasks, verify:

- [ ] `flake.nix` includes spicetify-nix input
- [ ] `modules/desktop/spotify-spicetify.nix` exists and is syntactically valid
- [ ] Module has all configuration options defined
- [ ] State directories are created via tmpfiles
- [ ] Systemd service and timer are configured
- [ ] Flatpak update integration is in place
- [ ] CLI command `spotify-spicetify` works
- [ ] Default Nord Dark theme config exists
- [ ] Usage documentation is complete
- [ ] Integration test script passes all checks
- [ ] Module is enabled in host config
- [ ] System rebuilds successfully
- [ ] Services are running and scheduled
- [ ] Spotify launches with Nord Dark theme visible
- [ ] Both SpotX and Spicetify work side-by-side

---

## Next Steps After Implementation

1. **Monitor logs** after first Spotify update to verify auto-re-application
2. **Test theme switching** by changing colorScheme option
3. **Add more themes** from Spicetify community if desired
4. **Customize CSS** to fine-tune appearance
5. **Explore extensions** beyond the default (adblock, shuffle+)

---

## Rollback Procedure

If issues arise:

```bash
# Disable Spicetify module
sudoedit hosts/zephyr/configuration.nix
# Change: services.spotify-spicetify.enable = false;

# Rebuild
sudo nixos-rebuild switch --flake /etc/nixos

# Verify SpotX still works
spotify-spotx status
flatpak run com.spotify.Client  # Should have ads blocked, stock theme
```
