# Flatpak Spotify + SpotX-Bash CI/CD Design

**Date:** 2026-03-02
**Author:** Claude Sonnet 4.6
**Status:** Approved

## Overview

Automated system to install Spotify via Flatpak, apply the SpotX-Bash ad-blocking patch, and automatically re-apply the patch whenever Spotify updates. The CI/CD system integrates with NixOS's existing Flatpak infrastructure.

## Problem Statement

- Spotify from nixpkgs cannot be patched with SpotX-Bash due to Nix store immutability
- Official Spotify via Flatpak works, but SpotX patch must be manually re-applied after each Spotify update
- Manual re-patching is error-prone and easy to forget

## Solution

Automated CI/CD pipeline that:
1. Installs Spotify Flatpak and applies initial SpotX patch
2. Monitors for Spotify version changes
3. Automatically re-applies SpotX patch after updates
4. Integrates seamlessly with existing NixOS Flatpak setup

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     CI/CD Flow                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Weekly Timer (flatpak-update.timer)                         │
│       ↓                                                      │
│  flatpak-update.service (updates all Flatpaks)              │
│       ↓                                                      │
│  spotx-patch.service (triggered by After=)                  │
│       ↓                                                      │
│  - Download latest SpotX script                             │
│  - Check if Spotify version changed                          │
│  - If changed: apply patch (retry 3x with backoff)          │
│  - Log results to journal                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Initial Setup Script

**Location:** `/var/lib/spotx/setup-spotify.sh`

**Purpose:** One-time installation and initial patching

**Responsibilities:**
- Install Spotify Flatpak from Flathub
- Download latest SpotX-Bash script
- Apply initial SpotX patch
- Initialize state tracking

### 2. Systemd Service

**Location:** `/etc/systemd/system/spotx-patch.service`

**Purpose:** Automated patching service

**Responsibilities:**
- Download fresh SpotX script from GitHub each run
- Get current Spotify Flatpak version
- Compare with stored version
- Apply patch if version changed
- Retry up to 3 times with exponential backoff
- Log all operations to systemd journal

**Configuration:**
```ini
[Service]
Type=oneshot
User=root
ExecStart=/var/lib/spotx/patch-manager.sh
```

### 3. Systemd Timer

**Location:** `/etc/systemd/system/spotx-patch.timer`

**Purpose:** Schedule patch checks and hook into Flatpak updates

**Configuration:**
```ini
[Timer]
OnCalendar=daily
Persistent=true
OnBootSec=10min

[Install]
WantedBy=timers.target
```

**Integration with Flatpak:**
```ini
# In flatpak-update.service:
Unit=flatpak-update.service
After=spotx-patch.service
```

### 4. State Management

**Location:** `/var/lib/spotx/`

**Files:**
- `version` - Last patched Spotify version (commit hash)
- `last-run` - Timestamp of last patch attempt
- `last-success` - Timestamp of last successful patch
- `retry-count` - Current retry attempt counter

## Data Flow

### Normal Flow (Version Changed)

```
1. Trigger (timer or after flatpak-update)
   ↓
2. Download SpotX script from GitHub
   ↓
3. Get Spotify version: flatpak info com.spotify.Client
   ↓
4. Compare with stored version in /var/lib/spotx/version
   ↓
5. Version changed:
   - Stop Spotify: flatpak kill com.spotify.Client
   - Apply SpotX patch
   - Verify: check for SpotX markers in Spotify files
   - Update stored version
   - Log: "Patched Spotify <version> with SpotX"
   ↓
6. Success → exit 0
```

### No-Op Flow (Version Unchanged)

```
1-4. Same as above
   ↓
5. Version unchanged:
   - Log: "Spotify unchanged, no patch needed"
   - Exit 0
```

### Error Flow

```
1-4. Same as above
   ↓
5. Error occurs:
   - Increment retry counter
   - If retry < 4:
     - Wait (exponential backoff: 5s, 15s, 45s)
     - Go to step 2
   - If retry == 4:
     - Log critical error with details
     - Exit 1 (failure)
```

## Error Handling

### Retry Strategy (Exponential Backoff)

| Attempt | Wait Time | Scenario |
|---------|-----------|----------|
| 1 | 0s | Immediate try |
| 2 | 5s | Transient network glitch |
| 3 | 15s | Temporary GitHub outage |
| 4 | 45s | Brief Spotify lock during update |

### Failure Scenarios

| Error | Action | Recovery |
|-------|--------|----------|
| Network down | Retry | Resolves when network returns |
| SpotX script 404 | Retry | Wait for GitHub or SpotX fix |
| Spotify not installed | Fail immediately | Run initial setup script |
| Patch fails | Retry | May require SpotX update for new Spotify |

### Logging

All events logged to systemd journal:
- `journalctl -u spotx-patch.service` - View patch service logs
- `journalctl -u spotx-patch.service -f` - Follow logs in real-time
- `journalctl --since today -u spotx-patch.service` - Today's activity

Log levels:
- `INFO` - Normal operations, version checks, successful patches
- `WARNING` - Retries, recoverable errors
- `ERROR` - Failed after all retries, critical issues

## Implementation Files

### NixOS Module

**Location:** `/etc/nixos/modules/desktop/spotify-spotx.nix`

**Enables:**
- Systemd service and timer
- State directory setup
- Integration with Flatpak module

### Scripts

**`/var/lib/spotx/setup-spotify.sh`** - Initial setup
**`/var/lib/spotx/patch-manager.sh`** - Main patch logic (called by systemd)
**`/var/lib/spotx/helpers.sh`** - Shared functions

### Systemd Units

**`/etc/systemd/system/spotx-patch.service`**
**`/etc/systemd/system/spotx-patch.timer`**

## Success Criteria

✅ Spotify Flatpak installed and accessible via Discover and CLI
✅ Initial SpotX patch applied successfully
✅ Systemd service and timer active and enabled
✅ Version tracking functional
✅ Automatic re-patching after Spotify updates
✅ All operations logged to systemd journal
✅ System survives reboots (state persists in `/var/lib/spotx/`)
✅ No manual intervention required after initial setup

## Testing

### Manual Testing

1. **Initial Setup:**
   ```bash
   /var/lib/spotx/setup-spotify.sh
   # Verify Spotify launches and has no ads
   ```

2. **Patch Service:**
   ```bash
   systemctl start spotx-patch.service
   journalctl -u spotx-patch.service -n 50
   ```

3. **Force Re-patch:**
   ```bash
   rm /var/lib/spotx/version
   systemctl start spotx-patch.service
   ```

4. **View Logs:**
   ```bash
   journalctl -u spotx-patch.service --since today
   ```

### Automated Testing

- Verify service starts: `systemctl is-active spotx-patch.service`
- Check timer scheduled: `systemctl list-timers | grep spotx`
- Confirm state files exist: `ls -la /var/lib/spotx/`

## Future Enhancements

1. **Desktop Notifications** - Optional: Show popup on successful patch
2. **Rollback** - If patch fails, revert to previous Spotify version
3. **Metrics** - Track patch success rate, timing
4. **Multiple Apps** - Extend pattern to other Flatpak apps needing patches

## References

- [SpotX Official](https://spotx-official.github.io/)
- [SpotX GitHub](https://github.com/SpotX-CLI/SpotX-Linux)
- [Flatpak Documentation](https://docs.flatpak.org)
- [Systemd Timer Documentation](https://man7.org/linux/man-pages/man5/systemd.timer.5.html)
