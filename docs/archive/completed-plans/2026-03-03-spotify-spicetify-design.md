# Spotify + Spicetify Integration Design

**Date:** 2026-03-03
**Author:** Claude Sonnet 4.6
**Status:** Approved
**Related:** [Spotify SpotX CI/CD Design](./2026-03-02-spotify-spotx-cicd-design.md)

## Overview

Declarative Spicetify integration for NixOS that runs side-by-side with the existing SpotX module, providing automated theming and extensions for Spotify Flatpak while maintaining independent operation and graceful failure handling.

## Problem Statement

- Spotify's default interface lacks personalization options
- Manual Spicetify setup breaks after every Spotify update
- No declarative configuration for Spicetify in NixOS ecosystem
- Existing tools (SpotX, Spicetify) conflict when not properly coordinated

## Solution

A dual-module architecture where:
1. **SpotX module** (existing) handles ad-blocking via official SpotX-Bash
2. **Spicetify module** (new) handles theming/extensions via spicetify-nix wrapper
3. Both operate independently on the same Spotify Flatpak installation
4. Systemd coordinates execution order (SpotX → Spicetify)
5. Auto-disable mechanism prevents broken themes from breaking Spotify

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  flake.nix                                                  │
│  ├─ inputs.spicetify-nix = "github:Gerg-L/spicetify-nix"   │
│  └─ modules/desktop/                                       │
│     ├─ spotify-spotx.nix (existing - unchanged)            │
│     └─ spotify-spicetify.nix (NEW)                         │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Daily Timer OR Flatpak Update Completion                  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  spotx-patch.service (existing)                             │
│  • Download SpotX script from GitHub                       │
│  • Check version against .spotx_patched marker             │
│  • Apply patch if changed                                   │
│  • Update version marker                                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ After=spotx-patch.service
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  spotify-spicetify.service (NEW)                            │
│  • Verify SpotX applied (check .spotx_patched)             │
│  • Check Spicetify version marker                          │
│  • Apply theme + extensions if needed                       │
│  • Update /var/lib/spicetify/version marker                │
│  • On failure: auto-disable + notify                       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Spotify Flatpak                                            │
│  /var/lib/flatpak/app/com.spotify.Client/                  │
│  └─ Apps/ (patched by both SpotX and Spicetify)           │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. NixOS Module: `spotify-spicetify.nix`

**Location:** `/etc/nixos/modules/desktop/spotify-spicetify.nix`

**Responsibilities:**
- Wrap `spicetify-nix` flake with NixOS-specific adaptations
- Create systemd service and timer
- Manage state directory (`/var/lib/spicetify/`)
- Provide `spotify-spicetify` CLI command
- Handle desktop notifications on success/failure

**Configuration Options:**

```nix
options.services.spotify-spicetify = {
  enable = mkEnableOption "Spotify theming and extensions via Spicetify";

  configPath = mkOption {
    type = types.nullOr types.path;
    default = null;
    description = "Path to custom Spicetify config directory. If null, uses default.";
  };

  theme = mkOption {
    type = types.nullOr types.str;
    default = "Dribbblish";
    description = "Theme name to apply. Set to null to disable theming.";
  };

  colorScheme = mkOption {
    type = types.str;
    default = "nord-dark";
    description = "Color scheme for theme (nord-dark, catppuccin, rosepine, etc.)";
  };

  customCSS = mkOption {
    type = types.lines;
    default = "";
    description = "Custom CSS to inject (merged with theme)";
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
    description = "Automatically re-apply Spicetify when Spotify updates";
  };

  checkInterval = mkOption {
    type = types.str;
    default = "daily";
    description = "How often to check and re-apply (systemd timer format)";
  };

  onFailure = mkOption {
    type = types.enum [ "disable" "notify-only" "ignore" ];
    default = "disable";
    description = "Behavior when Spicetify fails";
  };

  enableNotifications = mkOption {
    type = types.bool;
    default = true;
    description = "Send desktop notifications on success/failure";
  };

  preApplyHook = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = "Script to run before applying Spicetify";
  };

  postApplyHook = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = "Script to run after applying Spicetify";
  };
};
```

### 2. Default Configuration: Nord Dark Theme

**Location:** `/etc/nixos/config/spicetify/`

**Structure:**
```
/etc/nixos/config/spicetify/
├── themes/
│   └── Dribbblish/
│       ├── color.ini                    # Nord Dark color scheme
│       ├── user.css                     # Dribbblish CSS
│       └── README.md
├── extensions/
│   ├── adblock.js
│   ├── shuffle+.js
│   └── history.js
└── config.xini                          # Base Spicetify config
```

**Nord Dark Color Palette:**

```ini
[Nord Dark]
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
```

### 3. State Management

**Location:** `/var/lib/spicetify/`

**Files:**
```
/var/lib/spicetify/
├── backups/                           # Backup of Spotify Apps/ before customization
│   └── backup-<timestamp>/
├── version                            # Last successful Spicetify version
├── disabled                           # Exists if auto-disabled (contains reason)
└── config-applied                     # Hash of applied config (for change detection)
```

### 4. Systemd Service

**Location:** `/etc/systemd/system/spotify-spicetify.service`

**Configuration:**
```ini
[Unit]
Description=Spotify Spicetify Theme Service
After=spotx-patch.service
Wants=spotx-patch.service

[Service]
Type=oneshot
User=root
ExecStart=/etc/spicetify/patch-manager.sh apply
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Timer:**
```ini
[Unit]
Description=Spotify Spicetify Auto-Theme Timer

[Timer]
OnCalendar=daily
Persistent=true
OnBootSec=10min
Unit=spotify-spicetify.service

[Install]
WantedBy=timers.target
```

## Data Flow

### Normal Flow (Theme Applied)

```
1. Trigger: Daily timer OR flatpak-update.service completes
   ↓
2. Wait for spotx-patch.service to complete (After= dependency)
   ↓
3. Download latest Spicetify script from GitHub
   ↓
4. Get Spotify version: flatpak info com.spotify.Client
   ↓
5. Check if SpotX is applied (verify .spotx_patched exists)
   ↓
6. Compare current version with /var/lib/spicetify/version
   ↓
7. If versions differ:
   - Stop Spotify: flatpak kill com.spotify.Client
   - Backup Spotify Apps/ directory
   - Apply Spicetify theme + extensions
   - Write config to Spotify's prefs directory
   - Update /var/lib/spicetify/version
   ↓
8. Send desktop notification
   ↓
9. Log success to journal
   ↓
10. Exit 0
```

### No-Op Flow (Version Unchanged)

```
1-6. Same as above
   ↓
7. Version unchanged:
   - Log: "Spotify unchanged, no re-theme needed"
   - Exit 0
```

### Failure Flow (Auto-Disable)

```
1-6. Same as above
   ↓
7. Error occurs during theme application:
   - Write error details to /var/lib/spicetify/disabled
   - systemctl disable spotify-spicetify.service
   - systemctl stop spotify-spicetify.timer
   - Send desktop notification: "❌ Spicetify disabled due to errors"
   - Log critical error with details
   ↓
8. Exit 1 (SpotX continues working independently)
```

## Error Handling

### Error Categories

| Error Type | Detection | Recovery Strategy |
|------------|-----------|-------------------|
| **Spotify not patched** | Check `.spotx_patched` missing | Log warning, wait for SpotX, retry on next run |
| **Spicetify download fails** | curl/GitHub fetch errors | Retry 3x with exponential backoff (5s, 15s, 45s) |
| **Theme not found** | Theme directory missing | Log error, skip theme, apply extensions only |
| **Extension fails** | Extension injection error | Log warning, skip extension, continue with others |
| **Spotify won't stop** | `flatpak kill` timeout | Force kill, log warning, continue |
| **Critical failure** | Spicetify apply exits non-zero | Auto-disable if `onFailure = "disable"` |

### Retry Strategy

| Attempt | Wait Time | Scenario |
|---------|-----------|----------|
| 1 | 0s | Immediate try |
| 2 | 5s | Transient network glitch |
| 3 | 15s | Temporary GitHub outage |
| 4 | 45s | Brief Spotify lock during update |

## CLI Commands

**Command:** `spotify-spicetify`

**Subcommands:**
```bash
# Check status
spotify-spicetify status
# Output: Spicetify: applied (version: 2.37.1, theme: Dribbblish/nord-dark, extensions: adblock,shuffle+)

# Manually apply Spicetify
spotify-spicetify apply
spotify-spicetify apply --verbose
spotify-spicetify apply --theme catppuccin

# Disable/Enable
spotify-spicetify disable    # Remove Spicetify customizations
spotify-spicetify enable     # Re-enable after being disabled

# Logs
spotify-spicetify logs       # Show recent journal entries

# List available themes
spotify-spicetify list-themes

# Validate config
spotify-spicetify validate   # Check config syntax without applying

# Backup/restore
spotify-spicetify backup
spotify-spicetify restore [--backup-name backup-20260303]
```

## Configuration Examples

### Minimal (Default Nord Dark)

```nix
services.spotify-spicetify = {
  enable = true;
};
```

### Full Customization

```nix
services.spotify-spicetify = {
  enable = true;
  theme = "Dribbblish";
  colorScheme = "nord-dark";
  customCSS = ''
    .main-card-cardContainer {
      background: rgba(59, 66, 82, 0.8);
      backdrop-filter: blur(10px);
    }
  '';
  extensions = [ "adblock" "shuffle+" "history" "skipStats" ];
  customApps = [ "new-releases" "marketplace" ];
  autoApply = true;
  checkInterval = "daily";
  onFailure = "disable";
  enableNotifications = true;
};
```

### Custom Config Directory

```nix
services.spotify-spicetify = {
  enable = true;
  configPath = /etc/nixos/config/spicetify-custom;
  theme = "catppuccin";
  extensions = [ "adblock" "shuffle+" ];
};
```

### Spicetify-Only (No SpotX)

```nix
services.spotify-spotx.enable = false;  # Disable SpotX
services.spotify-spicetify = {
  enable = true;
  theme = "Dribbblish";
  extensions = [ "adblock" ];  # Use Spicetify's adblock instead
};
```

## Testing

### Pre-Installation Checklist

```bash
# 1. Verify Spotify Flatpak is installed
flatpak list | grep "com.spotify.Client"

# 2. Check SpotX is working
spotify-spotx status

# 3. Verify flatpak-update integration exists
systemctl status flatpak-update.service

# 4. Test systemd timer scheduling
systemctl list-timers | grep spotx
```

### Installation Testing

```bash
# After enabling the module and rebuilding:

# 1. Verify services are created
systemctl list-units | grep spotify

# 2. Check state directories exist
ls -la /var/lib/spicetify/

# 3. Verify CLI command works
spotify-spicetify status

# 4. Test theme application manually
spotify-spicetify apply --verbose

# 5. Launch Spotify and verify theme
flatpak run com.spotify.Client
```

### Integration Scenarios

1. **Fresh Install**
   - Enable module, rebuild, verify both SpotX and Spicetify apply on first boot

2. **Spotify Update Scenario**
   ```bash
   flatpak update com.spotify.Client
   # Verify both SpotX and Spicetify re-apply automatically
   ```

3. **Theme Switching**
   ```bash
   spotify-spicetify apply --color-scheme nord-dark
   spotify-spicetify apply --color-scheme rosepine
   ```

4. **Failure Recovery**
   ```bash
   # Simulate failure by removing Spotify
   sudo rm /var/lib/flatpak/app/com.spotify.Client/current/active
   sudo systemctl start spotify-spicetify.service
   # Verify auto-disable triggers correctly
   ```

### Success Criteria

✅ Spotify launches with Nord Dark theme applied
✅ No ads visible (SpotX working)
✅ Extensions functional (adblock, shuffle+, history)
✅ Both services enabled and scheduled
✅ Manual CLI commands work
✅ Theme persists after Spotify restart
✅ Both re-apply after Spotify update
✅ Auto-disable works on failure
✅ Desktop notifications appear

## Flake Inputs

**Add to `flake.nix`:**

```nix
{
  inputs = {
    # ... existing inputs
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, spicetify-nix, ... }: {
    nixosConfigurations.zephyr = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inputs = {
          inherit spicetify-nix;  # Add to specialArgs
          # ... other inputs
        };
      };
      modules = [
        ./hosts/zephyr/configuration.nix
        # ... other modules
      ];
    };
  };
}
```

## Notification Examples

**Success:**
```
🎵 Spicetify applied successfully
Theme: Dribbblish (Nord Dark)
Extensions: adblock, shuffle+, history
```

**Partial Failure:**
```
⚠️ Spicetify applied with warnings
Theme: Dribbblish ✓
Extensions: adblock ✓, shuffle+ ✗ (skipped), history ✓
Run 'spotify-spicetify logs' for details
```

**Auto-Disabled:**
```
❌ Spicetify disabled due to errors
Reason: Theme 'Dribbblish' not found
Spotify will continue with SpotX only (ads blocked)
To re-enable: sudo spotify-spicetify enable
Logs: journalctl -u spotify-spicetify.service
```

## Security Notes

- Spicetify scripts are downloaded from official GitHub repository
- Runs as root to access system Flatpak installation
- Only modifies Spotify Flatpak files (isolated from system)
- No user data is accessed or transmitted
- Auto-disable prevents repeated failed execution attempts

## Future Enhancements

1. **Additional Themes** - Add Catppuccin, Dracula, Rosepine as bundled options
2. **GUI Config Tool** - Web UI for selecting themes and customizing colors
3. **User-Level Configuration** - Per-user Spicetify configs via Home-Manager
4. **Theme Auto-Update** - Pull latest theme versions from community repos
5. **Metrics Dashboard** - Track theme application success/failure rates

## References

- [Spicetify Official Website](https://spicetify.app/)
- [Spicetify GitHub](https://github.com/spicetify/spicetify-cli)
- [Spicetify Themes](https://github.com/spicetify/spicetify-themes)
- [spicetify-nix](https://github.com/Gerg-L/spicetify-nix)
- [Nord Theme](https://github.com/arcticicestudio/nord)
- [Spotify Flatpak](https://flathub.org/apps/com.spotify.Client)
- [SpotX Integration](./2026-03-02-spotify-spotx-cicd-design.md)

## Implementation Plan

See [implementation plan](./2026-03-03-spotify-spicetify-implementation.md) for detailed step-by-step implementation guide.
