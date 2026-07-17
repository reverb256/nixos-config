# Plasma Configuration Sync - Zephyr to Nexus

**Created:** 2026-03-27
**Purpose:** Harmonize Nexus Plasma desktop with Zephyr's full configuration

## What Was Done

### 1. Declarative Configuration (NixOS)

**File:** `/etc/nixos/hosts/nexus/configuration.nix`

**Change:** Added `workstation` role profile to match Zephyr:

```nix
# Enable workstation role for full Plasma desktop environment
# This matches Zephyr's desktop setup (enables services.gaming)
profiles.role.workstation = true;
```

**Impact:** This enables the `services.gaming` module declaratively, matching Zephyr's setup.

### 2. Imperative Configuration (Plasma Settings)

**Script:** `/etc/nixos/scripts/sync-plasma-config.sh`

Comprehensive script to transfer ALL Plasma settings from Zephyr to Nexus, including:

#### Configuration Files (~/.config/)
- `kdeglobals` - Global KDE settings
- `kglobalshortcutsrc` - Global keyboard shortcuts
- `kwinrc` - KWin window manager settings
- `kwinrulesrc` - KWin window rules
- `kwinoutputconfig.json` - Display/output configuration
- `plasmashellrc` - Plasma shell settings
- `ksmserverrc` - Session management
- `dolphinrc` - Dolphin file manager
- `konsolerc` - Konsole terminal profiles
- `katerc` - Kate text editor
- `baloofilerc` - Baloo search settings
- And more...

#### Local Share Directories (~/.local/share/)
- `plasma/` - Plasma layouts, widgets, panels
- `kwin/` - KWin scripts and effects
- `konsole/` - Konsole profiles and color schemes
- `color-schemes/` - Custom color schemes
- `aurorae/` - Custom window decorations
- `desktopthemes/` - Custom Plasma themes
- `icons/` - Custom icon themes
- `templates/` - File templates

## How to Apply

### Step 1: Test NixOS Configuration

```bash
cd /etc/nixos
just check  # or nix flake check
```

### Step 2: Apply NixOS Changes

```bash
just switch  # or nixos-rebuild switch
```

### Step 3: Sync Plasma Settings

**Prerequisites:**
- Zephyr must be powered on and accessible via SSH
- SSH keys must be configured
- Network connectivity between hosts

**Run the sync script:**

```bash
sudo -u j_kro /etc/nixos/scripts/sync-plasma-config.sh
```

**What the script does:**
1. ✅ Checks connection to Zephyr
2. ✅ Creates backup of existing Nexus Plasma config
3. ✅ Transfers all Plasma config files from Zephyr
4. ✅ Transfers all Plasma themes, scripts, and effects
5. ✅ Sets correct ownership (j_kro:users)
6. ✅ Reports what was synced

### Step 4: Apply Plasma Changes

**Option A: Reboot (Recommended)**
```bash
sudo reboot
```

**Option B: Log out and back in**
1. Save all work
2. Log out of Plasma session
3. Log back in

## What Gets Synchronized

### Color & Visual Themes
- ✅ Color schemes (dark, light, custom)
- ✅ Application styles (Breeze, etc.)
- ✅ Window decorations (Aurorae themes)
- ✅ Desktop themes (Plasma look & feel)
- ✅ Icon themes
- ✅ Cursor themes
- ✅ Fonts

### KWin Window Manager
- ✅ KWin effects (blur, magic lamp, wobbly windows, etc.)
- ✅ KWin scripts (custom window behaviors)
- ✅ Window rules (application-specific behaviors)
- ✅ Desktop switching (virtual desktops)
- ✅ Activities
- ✅ Tiling layout

### Plasma Desktop
- ✅ Panel configuration (task manager, system tray)
- ✅ Desktop widgets (analog clock, system monitor, etc.)
- ✅ Right-click menu actions
- ✅ Kickoff launcher configuration
- ✅ Desktop layout and wallpaper

### Application Settings
- ✅ Dolphin (file manager settings, shortcuts)
- ✅ Konsole (profiles, color schemes, key bindings)
- ✅ Kate (editor settings, themes)
- ✅ Baloo (search indexing settings)
- ✅ KDE Wallet (password management)

### Keyboard & Input
- ✅ Global keyboard shortcuts
- ✅ Application-specific shortcuts
- ✅ Input methods

### Autostart
- ✅ Applications that start automatically
- ✅ Startup scripts

## Backup and Rollback

### Automatic Backup

The script creates automatic backups in `/tmp/plasma-backup-YYYYMMDD-HHMMSS/`

### Manual Rollback

If you need to revert to the previous Plasma configuration:

```bash
# Restore config files
cp -r /tmp/plasma-backup-YYYYMMDD-HHMMSS/* ~/.config/

# Restore local share files
cp -r /tmp/plasma-backup-YYYYMMDD-HHMMSS/* ~/.local/share/

# Log out and back in
```

## Troubleshooting

### Issue: Cannot connect to Zephyr

**Error:** `Cannot connect to zephyr`

**Solutions:**
1. Check if Zephyr is powered on: `ping 10.1.1.110`
2. Check SSH connectivity: `ssh j_kro@zephyr`
3. Verify SSH keys are configured

### Issue: Some Plasma settings not applied

**Solution:** Log out and back in (or reboot) to ensure all Plasma components reload the configuration.

### Issue: Broken Plasma configuration

**Solution:** Restore from backup:
```bash
# Find latest backup
ls -lt /tmp/plasma-backup-*

# Restore it
cp -r /tmp/plasma-backup-YYYYMMDD-HHMMSS/* ~/.config/
cp -r /tmp/plasma-backup-YYYYMMDD-HHMMSS/* ~/.local/share/
```

## Technical Details

### What the `workstation` Role Enables

Declaratively, `profiles.role.workstation = true` enables:

```nix
services.gaming.enable = true;
```

This includes:
- Gaming optimizations
- GameMode integration
- Gaming detection for workload coordination

### Why Sync Imperative Settings?

Plasma stores most of its configuration in user directories:

- **~/.config/** - Configuration files (text-based, easy to version control)
- **~/.local/share/** - Themes, scripts, layouts (binary data, complex structures)

These cannot be easily managed declaratively in NixOS, so we sync them as files.

## Verification

After syncing and logging back in, verify:

1. **Color scheme matches Zephyr**
   - Right-click desktop → Configure Desktop and Behavior → Colors
   - Check current color scheme

2. **KWin effects working**
   - System Settings → Workspace Behavior → Desktop Effects
   - Verify effects are enabled

3. **Panels and widgets match**
   - Check panel layout
   - Check desktop widgets

4. **Keyboard shortcuts work**
   - Test a few global shortcuts
   - Check System Settings → Shortcuts

## Next Steps

### Optional: Create Git Repository for Plasma Config

To track changes to your Plasma configuration:

```bash
cd ~
mkdir -p .config/plasma-git
cd .config/plasma-git

# Initialize repo
git init

# Add Plasma configs
git add ~/.config/kdeglobals
git add ~/.config/kglobalshortcutsrc
git add ~/.config/kwinrc
git add ~/.config/plasmashellrc
git add ~/.config/konsolerc
git add ~/.local/share/plasma/
git add ~/.local/share/konsole/
git add ~/.local/share/color-schemes/

# Commit
git commit -m "Initial Plasma config from Zephyr sync"
```

Then you can track changes over time and easily revert unwanted modifications.

## Related Files

- **NixOS config:** `/etc/nixos/hosts/nexus/configuration.nix`
- **Sync script:** `/etc/nixos/scripts/sync-plasma-config.sh`
- **Role profiles:** `/etc/nixos/modules/profiles/role/default.nix`
- **Desktop module:** `/etc/nixos/modules/desktop/plasma6.nix`

## Summary

✅ **Declarative:** Added `profiles.role.workstation = true` to Nexus config
✅ **Imperative:** Created comprehensive sync script for all Plasma settings
✅ **Backup:** Automatic backup before any changes
✅ **Rollback:** Easy restore if needed

Your Nexus Plasma desktop will now match Zephyr's configuration!
