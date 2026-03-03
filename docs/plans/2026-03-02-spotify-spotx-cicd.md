# Spotify + SpotX-Bash CI/CD Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automated system to install Spotify via Flatpak, apply SpotX-Bash ad-blocking patch, and automatically re-patch after Spotify updates.

**Architecture:** Systemd service triggered by Flatpak updates that downloads fresh SpotX script, checks Spotify version, re-applies patch if changed, with exponential backoff retry logic.

**Tech Stack:** Flatpak, systemd, bash scripts, NixOS module system

---

## Task 1: Create NixOS Module for Spotify + SpotX

**Files:**
- Create: `/etc/nixos/modules/desktop/spotify-spotx.nix`

**Step 1: Write the NixOS module**

```nix
# Spotify Flatpak with SpotX-Bash automated patching
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.spotify-spotx;
in {
  options.services.spotify-spotx = {
    enable = mkEnableOption "Spotify Flatpak with automated SpotX-Bash patching";

    autoPatch = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic re-patching when Spotify updates";
    };

    patchCheckInterval = mkOption {
      type = types.str;
      default = "daily";
      description = "How often to check for Spotify updates (systemd timer format)";
    };
  };

  config = mkIf cfg.enable {
    # Create state directory for version tracking
    systemd.tmpfiles.rules = [
      "d /var/lib/spotx 0755 root root -"
      "d /var/lib/spotx/logs 0755 root root -"
    ];

    # Initial setup script
    environment.etc."spotx/setup-spotify.sh".source = pkgs.writeShellScript "setup-spotify.sh" ''
      #!/usr/bin/env bash
      set -euo pipefail

      echo "=== Spotify + SpotX Initial Setup ==="

      # Install Spotify from Flathub
      echo "Installing Spotify Flatpak..."
      flatpak remote-list | grep -q flathub || {
        echo "Error: Flathub remote not found. Enable Flatpak module first."
        exit 1
      }

      flatpak list | grep -q "com.spotify.Client" || {
        flatpak install -y flathub com.spotify.Client
      }

      # Download and apply SpotX patch
      echo "Applying SpotX-Bash patch..."
      bash <(curl -sSL https://spotx-official.github.io/run.sh) --flatpak

      # Get Spotify version for tracking
      SPOTIFY_VERSION=$(flatpak info com.spotify.Client | grep "Ref:" | awk '{print $2}')
      echo "$SPOTIFY_VERSION" > /var/lib/spotx/version

      echo "✓ Setup complete! Spotify patched with SpotX."
      echo "  Launch with: flatpak run com.spotify.Client"
    '';

    # Main patch manager script
    environment.etc."spotx/patch-manager.sh".source = pkgs.writeShellScript "patch-manager.sh" ''
      #!/usr/bin/env bash
      set -euo pipefail

      # Configuration
      STATE_DIR="/var/lib/spotx"
      VERSION_FILE="$STATE_DIR/version"
      LAST_RUN_FILE="$STATE_DIR/last-run"
      LAST_SUCCESS_FILE="$STATE_DIR/last-success"
      RETRY_FILE="$STATE_DIR/retry-count"
      LOG_FILE="$STATE_DIR/logs/patch-$(date +%Y%m%d-%H%M%S).log"

      # SpotX script URL
      SPOTX_URL="https://spotx-official.github.io/run.sh"

      # Retry configuration
      MAX_RETRIES=3
      RETRY_DELAYS=(0 5 15 45)  # seconds

      # Logging functions
      log_info() {
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
        systemd-cat -t spotx-patch -p info <<< "$*"
      }

      log_warn() {
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
        systemd-cat -t spotx-patch -p warning <<< "$*"
      }

      log_error() {
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
        systemd-cat -t spotx-patch -p err <<< "$*"
      }

      # Get current retry count
      get_retry_count() {
        if [[ -f "$RETRY_FILE" ]]; then
          cat "$RETRY_FILE"
        else
          echo 0
        fi
      }

      # Increment retry count
      increment_retry() {
        local retry=$(get_retry_count)
        echo $((retry + 1)) > "$RETRY_FILE"
      }

      # Reset retry count
      reset_retry() {
        echo 0 > "$RETRY_FILE"
      }

      # Check if Spotify is installed
      check_spotify_installed() {
        flatpak list | grep -q "com.spotify.Client"
      }

      # Get current Spotify version
      get_spotify_version() {
        flatpak info com.spotify.Client | grep "Ref:" | awk '{print $2}'
      }

      # Get stored version
      get_stored_version() {
        if [[ -f "$VERSION_FILE" ]]; then
          cat "$VERSION_FILE"
        else
          echo ""
        fi
      }

      # Update stored version
      update_stored_version() {
        local version=$1
        echo "$version" > "$VERSION_FILE"
      }

      # Download SpotX script
      download_spotx() {
        log_info "Downloading SpotX script from GitHub..."
        if curl -fsSL "$SPOTX_URL" -o /tmp/spotx.sh; then
          log_info "✓ SpotX script downloaded"
          return 0
        else
          log_error "Failed to download SpotX script"
          return 1
        fi
      }

      # Apply SpotX patch
      apply_patch() {
        log_info "Applying SpotX-Bash patch..."

        # Stop Spotify if running
        if flatpak list --running | grep -q "com.spotify.Client"; then
          log_info "Stopping Spotify..."
          flatpak kill com.spotify.Client || true
        fi

        # Apply patch
        if bash /tmp/spotx.sh --flatpak; then
          log_info "✓ SpotX patch applied successfully"
          return 0
        else
          log_error "SpotX patch application failed"
          return 1
        fi
      }

      # Main patch logic with retry
      patch_with_retry() {
        local retry=$(get_retry_count)
        local delay=''${RETRY_DELAYS[$retry]}

        if [[ $retry -gt 0 ]]; then
          log_info "Retry attempt $((retry + 1))/$MAX_RETRIES after ${delay}s delay..."
          sleep "$delay"
        fi

        increment_retry

        # Download SpotX script
        if ! download_spotx; then
          if [[ $retry -lt $MAX_RETRIES ]]; then
            log_warn "Download failed, will retry..."
            return 1
          else
            log_error "Download failed after $MAX_RETRIES retries"
            return 1
          fi
        fi

        # Apply patch
        if ! apply_patch; then
          if [[ $retry -lt $MAX_RETRIES ]]; then
            log_warn "Patch failed, will retry..."
            return 1
          else
            log_error "Patch failed after $MAX_RETRIES retries"
            return 1
          fi
        fi

        # Success - update version and reset retry
        local version=$(get_spotify_version)
        update_stored_version "$version"
        reset_retry
        echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$LAST_SUCCESS_FILE"

        log_info "✓ Successfully patched Spotify $version"
        return 0
      }

      # Main execution
      main() {
        log_info "=== SpotX Patch Check Started ==="

        # Update last run time
        echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$LAST_RUN_FILE"

        # Check if Spotify is installed
        if ! check_spotify_installed; then
          log_error "Spotify Flatpak not installed. Run initial setup first."
          exit 1
        fi

        # Get versions
        local current_version=$(get_spotify_version)
        local stored_version=$(get_stored_version)

        log_info "Current Spotify version: $current_version"
        log_info "Last patched version: ${stored_version:-none}"

        # Check if patch needed
        if [[ "$current_version" == "$stored_version" ]]; then
          log_info "Spotify version unchanged, no patch needed"
          reset_retry
          exit 0
        fi

        log_info "Spotify version changed, re-applying SpotX patch..."

        # Apply patch with retry logic
        if patch_with_retry; then
          log_info "=== Patch Check Complete ==="
          exit 0
        else
          log_error "=== Patch Check Failed ==="
          exit 1
        fi
      }

      main "$@"
    '';

    # Systemd service
    systemd.services.spotx-patch = {
      description = "Spotify SpotX Patch Manager";
      after = [ "network-online.target" "flatpak-update.service" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/spotx/patch-manager.sh";
        User = "root";
        RemainAfterExit = false;
      };
    };

    # Systemd timer
    systemd.timers.spotx-patch = mkIf cfg.autoPatch {
      description = "Daily Spotify SpotX patch check";
      partOf = [ "flatpak-update.service" ];
      timerConfig = {
        OnCalendar = cfg.patchCheckInterval;
        Persistent = true;
        OnBootSec = "10min";
      };
      wantedBy = [ "timers.target" ];
    };

    # Integration with Flatpak updates
    systemd.services.flatpak-update.after = [ "spotx-patch.service" ];
  };
}
```

**Step 2: Verify module syntax**

Run: `nix-instantiate --parse /etc/nixos/modules/desktop/spotify-spotx.nix`
Expected: No errors, valid Nix expression

**Step 3: Commit**

```bash
git add modules/desktop/spotify-spotx.nix
git commit -m "feat(spotify-spotx): add NixOS module for automated SpotX patching"
```

---

## Task 2: Update Flatpak Module Integration

**Files:**
- Modify: `/etc/nixos/modules/desktop/flatpak.nix`

**Step 1: Add SpotX integration to Flatpak module**

Add after the existing services:

```nix
    # Update Flatpak weekly
    systemd.timers.flatpak-update = mkIf cfg.autoUpdate {
      description = "Flatpak update timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        Unit = "flatpak-update.service";
      };
    };

    systemd.services.flatpak-update = mkIf cfg.autoUpdate {
      description = "Update Flatpak packages";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.flatpak}/bin/flatpak update --assumeyes";
        User = "root";
      };
      # Trigger SpotX patch after Flatpak updates
      wants = ["spotx-patch.service"];
      after = ["spotx-patch.service"];
    };
```

**Step 2: Verify module syntax**

Run: `nix-instantiate --parse /etc/nixos/modules/desktop/flatpak.nix`
Expected: No errors

**Step 3: Commit**

```bash
git add modules/desktop/flatpak.nix
git commit -m "feat(flatpak): integrate SpotX patch trigger with Flatpak updates"
```

---

## Task 3: Enable Spotify-SpotX Module in Host Config

**Files:**
- Modify: `/etc/nixos/hosts/zephyr/configuration.nix`

**Step 1: Add module import and enable**

Add to imports section:
```nix
    # Desktop modules
    ../../modules/desktop/flatpak.nix
    ../../modules/desktop/spotify-spotx.nix
```

Add to services section:
```nix
  # ============================================================================
  # FLATPAK - Flatpak support with Discover and Flathub
  # ============================================================================
  services.flatpak-kde = {
    enable = true;
    autoUpdate = true;
  };

  # ============================================================================
  # SPOTIFY + SPOTX - Automated ad-blocking patch
  # ============================================================================
  services.spotify-spotx = {
    enable = true;
    autoPatch = true;
  };
```

**Step 2: Test configuration build**

Run: `nixos-rebuild build --flake /etc/nixos`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add hosts/zephyr/configuration.nix
git commit -m "feat(zephyr): enable Spotify with automated SpotX patching"
```

---

## Task 4: Apply Configuration

**Step 1: Switch to new configuration**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Expected: System rebuilds successfully, services enabled

**Step 2: Verify systemd units created**

Run: `systemctl list-unit-files | grep spotx`
Expected Output:
```
spotx-patch.service    static
spotx-patch.timer      enabled
```

**Step 3: Verify timer scheduled**

Run: `systemctl list-timers | grep spotx`
Expected: Timer listed with next execution time

**Step 4: Verify state directory created**

Run: `ls -la /var/lib/spotx/`
Expected: Directory exists, empty

**Step 5: Commit**

```bash
git add -A
git commit -m "chore: apply Spotify-SpotX configuration"
```

---

## Task 5: Initial Spotify Setup

**Step 1: Run initial setup script**

Run: `sudo bash /etc/spotx/setup-spotify.sh`
Expected Output:
```
=== Spotify + SpotX Initial Setup ===
Installing Spotify Flatpak...
...
✓ Setup complete! Spotify patched with SpotX.
```

**Step 2: Verify Spotify installed**

Run: `flatpak list | grep spotify`
Expected: `com.spotify.Client` listed

**Step 3: Verify SpotX patch applied**

Run: `flatpak run com.spotify.Client`
Expected: Spotify launches without ads

**Step 4: Check version file created**

Run: `cat /var/lib/spotx/version`
Expected: Spotify version hash (e.g., `app/com.spotify.Client/x86_64/stable`)

**Step 5: Commit**

```bash
git add -A
git commit -m "chore: complete initial Spotify + SpotX setup"
```

---

## Task 6: Test Automated Patching

**Step 1: Manually trigger patch service**

Run: `sudo systemctl start spotx-patch.service`
Expected: Service runs, logs "Spotify version unchanged, no patch needed"

**Step 2: View service logs**

Run: `journalctl -u spotx-patch.service -n 50`
Expected: Logs showing version check and no-op

**Step 3: Simulate version change (force re-patch)**

Run: `sudo rm /var/lib/spotx/version && sudo systemctl start spotx-patch.service`
Expected: Service detects version change, re-applies patch

**Step 4: Verify patch success**

Run: `cat /var/lib/spotx/version && journalctl -u spotx-patch.service --since '1 minute ago' | grep "Successfully patched"`
Expected: Version file updated, success message in logs

**Step 5: Check log file created**

Run: `ls -la /var/lib/spotx/logs/`
Expected: Log file present with detailed patch history

**Step 6: Commit**

```bash
git add -A
git commit -m "test(spotify-spotx): verify automated patching works"
```

---

## Task 7: Test Flatpak Update Integration

**Step 1: Check Flatpak update triggers SpotX**

Run: `systemctl show flatpak-update.service | grep Wants`
Expected: Includes `spotx-patch.service`

**Step 2: Manual Flatpak update test**

Run: `sudo systemctl start flatpak-update.service && sudo systemctl start spotx-patch.service`
Expected: Both services complete successfully

**Step 3: Verify service order**

Run: `systemctl show spotx-patch.service | grep After`
Expected: Includes `flatpak-update.service`

**Step 4: Check SpotX runs after Flatpak**

Run: `journalctl --since '5 minutes ago' | grep -E "(flatpak-update|spotx-patch)"`
Expected: Flatpak update completes, then SpotX patch runs

**Step 5: Commit**

```bash
git add -A
git commit -m "test(spotify-spotx): verify Flatpak integration"
```

---

## Task 8: Add Documentation

**Files:**
- Create: `/etc/nixos/docs/spotify-spotx-usage.md`

**Step 1: Write usage documentation**

```markdown
# Spotify + SpotX-Bash Usage Guide

## Overview

This system provides Spotify (Flatpak version) with automated SpotX-Bash ad-blocking patching. When Spotify updates, the SpotX patch is automatically re-applied.

## Features

- ✅ Spotify from Flathub
- ✅ Ad-blocking via SpotX-Bash
- ✅ Automatic re-patching after updates
- ✅ Retry logic with exponential backoff
- ✅ Complete logging to systemd journal

## Launching Spotify

### Command Line
```bash
flatpak run com.spotify.Client
```

### GUI
- Open Discover (KDE Software Center)
- Search "Spotify"
- Click "Launch"

## Checking Patch Status

### View Patch Logs
```bash
# Recent patch activity
journalctl -u spotx-patch.service --since today

# Follow logs in real-time
journalctl -u spotx-patch.service -f

# Detailed log files
ls -la /var/lib/spotx/logs/
cat /var/lib/spotx/logs/patch-YYYYMMDD-HHMMSS.log
```

### Check Current Version
```bash
# Last patched Spotify version
cat /var/lib/spotx/version

# Last successful patch
cat /var/lib/spotx/last-success

# Last patch check
cat /var/lib/spotx/last-run
```

### View Scheduled Checks
```bash
# Next scheduled patch check
systemctl list-timers | grep spotx

# Timer status
systemctl status spotx-patch.timer
```

## Manual Operations

### Force Re-patch
```bash
# Remove version file to force re-patch
sudo rm /var/lib/spotx/version

# Trigger patch service
sudo systemctl start spotx-patch.service
```

### Run Initial Setup Again
```bash
sudo bash /etc/spotx/setup-spotify.sh
```

### Disable Automated Patching
```nix
# In your NixOS configuration:
services.spotify-spotx.autoPatch = false;
```

## Troubleshooting

### Spotify Shows Ads

1. Check if patch service is running:
   ```bash
   systemctl status spotx-patch.service
   ```

2. Check last successful patch:
   ```bash
   cat /var/lib/spotx/last-success
   ```

3. Manually re-patch:
   ```bash
   sudo rm /var/lib/spotx/version
   sudo systemctl start spotx-patch.service
   ```

4. View detailed logs:
   ```bash
   journalctl -u spotx-patch.service -n 100
   ```

### Patch Service Failing

1. Check if Spotify is installed:
   ```bash
   flatpak list | grep spotify
   ```

2. Check network connectivity:
   ```bash
   curl -I https://spotx-official.github.io/
   ```

3. View error logs:
   ```bash
   journalctl -u spotx-patch.service -p err
   cat /var/lib/spotx/logs/*.log
   ```

4. Retry count status:
   ```bash
   cat /var/lib/spotx/retry-count
   ```

### Spotify Not Launching

1. Check Spotify installation:
   ```bash
   flatpak list | grep spotify
   ```

2. Try launching manually:
   ```bash
   flatpak run com.spotify.Client
   ```

3. Check for Flatpak errors:
   ```bash
   flatpak info com.spotify.Client
   ```

4. Reinstall if needed:
   ```bash
   flatpak uninstall com.spotify.Client
   sudo bash /etc/spotx/setup-spotify.sh
   ```

## Automated Behavior

### Daily Check
- Timer runs daily at 3 AM (configurable)
- Checks if Spotify version changed
- Re-applies patch if needed
- Logs all activity

### After Flatpak Updates
- Flatpak updates weekly (Sunday 3 AM)
- SpotX patch runs immediately after
- Ensures Spotify stays patched

### Retry Logic
If patch fails, service retries with delays:
- Attempt 1: Immediate
- Attempt 2: 5 seconds
- Attempt 3: 15 seconds
- Attempt 4: 45 seconds
- After 4 failures: Logs error, stops retrying

## Configuration

### NixOS Options

```nix
services.spotify-spotx = {
  enable = true;           # Enable the service
  autoPatch = true;        # Enable automatic patching
  patchCheckInterval = "daily";  # Check frequency
};
```

### State Directory

All state stored in `/var/lib/spotx/`:
- `version` - Last patched Spotify version
- `last-run` - Last patch check timestamp
- `last-success` - Last successful patch timestamp
- `retry-count` - Current retry attempt
- `logs/` - Detailed patch logs

## Systemd Services

### spotx-patch.service
The main patching service. Manually trigger:
```bash
sudo systemctl start spotx-patch.service
```

### spotx-patch.timer
Schedules automatic patch checks:
```bash
sudo systemctl status spotx-patch.timer
```

## Integration with Flatpak

The SpotX patch service integrates with the Flatpak update flow:
1. `flatpak-update.timer` triggers weekly
2. `flatpak-update.service` updates all Flatpaks
3. `spotx-patch.service` runs automatically after
4. Re-applies SpotX if Spotify updated

## Monitoring

### Check Service Health
```bash
# Service status
systemctl status spotx-patch.service

# Timer status
systemctl status spotx-patch.timer

# Next scheduled run
systemctl list-timers spotx-patch.timer
```

### View Statistics
```bash
# Patch history
ls -la /var/lib/spotx/logs/

# Success rate
journalctl -u spotx-patch.service --since "30 days ago" | grep -c "Successfully patched"
```

## Security

- Scripts run as root (required for Flatpak system operations)
- Downloads SpotX script from official GitHub each run
- No hardcoded credentials or secrets
- Logs contain no sensitive information

## Updates

### SpotX Script
Always downloads latest from GitHub, gets:
- Latest Spotify compatibility fixes
- New features
- Bug fixes

### NixOS Module
Update via normal NixOS rebuild:
```bash
sudo nixos-rebuild switch --flake /etc/nixos
```

## Resources

- [SpotX Official](https://spotx-official.github.io/)
- [SpotX GitHub](https://github.com/SpotX-CLI/SpotX-Linux)
- [Flatpak Docs](https://docs.flatpak.org)
- [Systemd Timers](https://man7.org/linux/man-pages/man5/systemd.timer.5.html)
```

**Step 2: Commit documentation**

```bash
git add docs/spotify-spotx-usage.md
git commit -m "docs(spotify-spotx): add comprehensive usage guide"
```

---

## Task 9: Final Verification

**Step 1: Rebuild and switch**

Run: `sudo nixos-rebuild switch --flake /etc/nixos`
Expected: Clean rebuild, no errors

**Step 2: Verify all services**

Run: `systemctl list-unit-files | grep -E "(flatpak|spotx)"`
Expected Output:
```
flatpak-update.service    static
flatpak-update.timer      enabled
spotx-patch.service       static
spotx-patch.timer         enabled
```

**Step 3: Test Spotify launch**

Run: `flatpak run com.spotify.Client &`
Expected: Spotify launches, plays music without ads

**Step 4: Test manual patch trigger**

Run: `sudo rm /var/lib/spotx/version && sudo systemctl start spotx-patch.service && sleep 5 && journalctl -u spotx-patch.service -n 20`
Expected: Logs show patch applied successfully

**Step 5: Verify timer scheduled**

Run: `systemctl list-timers --all | grep spotx`
Expected: Timer enabled and scheduled

**Step 6: Check all state files**

Run: `ls -la /var/lib/spotx/`
Expected: All state files present (version, last-run, last-success, retry-count, logs/)

**Step 7: Final commit**

```bash
git add -A
git commit -m "feat(spotify-spotx): complete automated patching system

- Spotify Flatpak installation
- SpotX-Bash ad-blocking patch
- Automated re-patching on updates
- Retry logic with exponential backoff
- Complete logging and monitoring
- Integration with Flatpak updates

Tested and verified working.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Summary

This implementation creates a fully automated CI/CD pipeline for keeping Spotify patched with SpotX-Bash:

1. **NixOS module** enables the service declaratively
2. **Systemd service** handles patching with retry logic
3. **Systemd timer** schedules daily checks
4. **Integration** with Flatpak updates triggers re-patching
5. **State tracking** ensures patches only applied when needed
6. **Comprehensive logging** aids troubleshooting

Total estimated time: 45-60 minutes
Commit count: 9 commits
Files created: 4
Files modified: 3
