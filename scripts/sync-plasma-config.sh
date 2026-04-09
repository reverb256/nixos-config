#!/usr/bin/env bash
# Plasma Configuration Sync - Zephyr to Nexus
# Transfers ALL Plasma settings from Zephyr to Nexus
#
# Usage: sudo -u j_kro /etc/nixos/scripts/sync-plasma-config.sh

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }

# Configuration
ZEPHYR_HOST="zephyr"
SOURCE_USER="j_kro"
TARGET_USER="j_kro"
BACKUP_DIR="/tmp/plasma-backup-$(date +%Y%m%d-%H%M%S)"
TEMP_DIR="/tmp/plasma-sync-$$"

# Cleanup on exit
trap "rm -rf $TEMP_DIR" EXIT

log "=== Plasma Configuration Sync: Zephyr → Nexus ==="
echo ""

# Check if Zephyr is reachable
log "Checking connection to Zephyr..."
if ! ssh -o ConnectTimeout=5 "${SOURCE_USER}@${ZEPHYR_HOST}" "echo 'Connected'" >/dev/null 2>&1; then
    log_error "Cannot connect to ${ZEPHYR_HOST}"
    log_error "Please ensure:"
    log_error "  1. Zephyr is powered on"
    log_error "  2. Network connectivity is working"
    log_error "  3. SSH keys are configured"
    exit 1
fi
log_success "Connected to ${ZEPHYR_HOST}"
echo ""

# Create backup
log "Creating backup of existing Nexus Plasma config..."
mkdir -p "$BACKUP_DIR"
cp -r /home/${TARGET_USER}/.config/k* "$BACKUP_DIR/" 2>/dev/null || true
cp -r /home/${TARGET_USER}/.local/share/plasma* "$BACKUP_DIR/" 2>/dev/null || true
cp -r /home/${TARGET_USER}/.local/share/kwin "$BACKUP_DIR/" 2>/dev/null || true
cp -r /home/${TARGET_USER}/.local/share/konsole "$BACKUP_DIR/" 2>/dev/null || true
cp -r /home/${TARGET_USER}/.local/share/color-schemes "$BACKUP_DIR/" 2>/dev/null || true
cp -r /home/${TARGET_USER}/.local/share/aurorae "$BACKUP_DIR/" 2>/dev/null || true
cp -r /home/${TARGET_USER}/.local/share/desktopthemes "$BACKUP_DIR/" 2>/dev/null || true
log_success "Backup saved to: $BACKUP_DIR"
echo ""

# Create temp directory
mkdir -p "$TEMP_DIR"

log "Fetching Plasma configuration from Zephyr..."
echo ""

# Define files and directories to sync
declare -a CONFIG_FILES=(
    "kdeglobals"
    "kglobalshortcutsrc"
    "kwinrc"
    "kwinrulesrc"
    "kwinoutputconfig.json"
    "plasmashellrc"
    "ksmserverrc"
    "dolphinrc"
    "konsolerc"
    "katerc"
    "baloofilerc"
    "baloofileinformationrc"
    "kcminputrc"
    "kscreenlockerrc"
    "kwalletrc"
    "kdedrc"
)

declare -a CONFIG_DIRS=(
    "autostart"
)

declare -a SHARE_DIRS=(
    "plasma"
    "kwin"
    "konsole"
    "color-schemes"
    "aurorae"
    "desktopthemes"
    "kstyle"
    "templates"
)

# Function to sync a file
sync_file() {
    local file="$1"
    log "Syncing ~/.config/${file}..."
    if scp "${SOURCE_USER}@${ZEPHYR_HOST}:~/.config/${file}" "$TEMP_DIR/" 2>/dev/null; then
        cp -f "$TEMP_DIR/${file}" "/home/${TARGET_USER}/.config/${file}"
        chown ${TARGET_USER}:users "/home/${TARGET_USER}/.config/${file}"
        log_success "Synced ${file}"
    else
        log_warn "File not found on Zephyr: ${file}"
    fi
}

# Function to sync a directory
sync_dir() {
    local dir="$1"
    local source_path="$2"
    local target_path="$3"

    log "Syncing ${target_path}..."
    if ssh "${SOURCE_USER}@${ZEPHYR_HOST}" "[ -d '${source_path}' ]" 2>/dev/null; then
        mkdir -p "${target_path}"
        rsync -av --delete "${SOURCE_USER}@${ZEPHYR_HOST}:${source_path}/" "${target_path}/"
        chown -R ${TARGET_USER}:users "${target_path}"
        log_success "Synced $(basename ${target_path})"
    else
        log_warn "Directory not found on Zephyr: ${source_path}"
    fi
}

# Sync config files
log "────────────────────────────────────────"
log "Syncing KDE/Plasma config files..."
log "────────────────────────────────────────"
for file in "${CONFIG_FILES[@]}"; do
    sync_file "$file"
done
echo ""

# Sync config directories
log "────────────────────────────────────────"
log "Syncing config directories..."
log "────────────────────────────────────────"
for dir in "${CONFIG_DIRS[@]}"; do
    sync_dir "$dir" "~/.config/${dir}" "/home/${TARGET_USER}/.config/${dir}"
done
echo ""

# Sync share directories
log "────────────────────────────────────────"
log "Syncing local share directories..."
log "────────────────────────────────────────"
for dir in "${SHARE_DIRS[@]}"; do
    sync_dir "$dir" "~/.local/share/${dir}" "/home/${TARGET_USER}/.local/share/${dir}"
done
echo ""

# Sync icon themes (if any custom ones)
log "────────────────────────────────────────"
log "Checking for custom icon themes..."
log "────────────────────────────────────────"
if ssh "${SOURCE_USER}@${ZEPHYR_HOST}" "[ -d ~/.local/share/icons ]" 2>/dev/null; then
    log "Found custom icons, syncing..."
    sync_dir "icons" "~/.local/share/icons" "/home/${TARGET_USER}/.local/share/icons"
else
    log_warn "No custom icon themes found on Zephyr"
fi
echo ""

# Summary
log "────────────────────────────────────────"
log "Sync Complete!"
log "────────────────────────────────────────"
echo ""
log "What was synced:"
log "  ✓ KDE/Plasma configuration files"
log "  ✓ Color schemes and themes"
log "  ✓ KWin scripts, effects, and rules"
log "  ✓ Plasma desktop layouts"
log "  ✓ Keyboard shortcuts"
log "  ✓ Application configs (Dolphin, Konsole, etc.)"
log "  ✓ Autostart applications"
log "  ✓ Custom themes and icons"
echo ""
log_success "All Plasma settings transferred from Zephyr to Nexus"
echo ""
log "To apply changes:"
log "  1. Log out of current Plasma session"
log "  2. Log back in (or reboot)"
log ""
log "To restore backup if needed:"
log "  cp -r ${BACKUP_DIR}/* /home/${TARGET_USER}/.config/"
log "  cp -r ${BACKUP_DIR}/* /home/${TARGET_USER}/.local/share/"
echo ""
