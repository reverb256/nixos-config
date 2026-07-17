# Quick Reference: Plasma Sync Commands

## Test and Apply NixOS Config
```bash
cd /etc/nixos
just check      # Validate configuration
just switch     # Apply to local host
```

## Sync Plasma Settings from Zephyr
```bash
# Run as j_kro user (not root!)
sudo -u j_kro /etc/nixos/scripts/sync-plasma-config.sh
```

## What Gets Synced
✅ Color schemes & themes
✅ KWin effects & scripts
✅ Plasma layouts & widgets
✅ Keyboard shortcuts
✅ Application configs (Dolphin, Konsole, etc.)
✅ Autostart applications
✅ All ~/.config/k* configs
✅ All ~/.local/share/plasma* themes

## Apply Changes
```bash
# Option 1: Reboot (recommended)
sudo reboot

# Option 2: Log out and back in
# Save work → Log out → Log in
```

## Rollback if Needed
```bash
# Find latest backup
ls -lt /tmp/plasma-backup-*

# Restore it
cp -r /tmp/plasma-backup-YYYYMMDD-HHMMSS/* ~/.config/
cp -r /tmp/plasma-backup-YYYYMMDD-HHMMSS/* ~/.local/share/

# Log out and back in
```

## Files Created/Modified
- `/etc/nixos/hosts/nexus/configuration.nix` - Added workstation role
- `/etc/nixos/scripts/sync-plasma-config.sh` - Sync script
- `/etc/nixos/docs/PLASMA_SYNC_ZEPHYR_TO_NEXUS.md` - Full documentation

## Prerequisites
- ✅ Zephyr powered on and accessible
- ✅ SSH keys configured
- ✅ Network connectivity working
