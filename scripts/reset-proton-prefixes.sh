#!/usr/bin/env bash
# Script to reset Proton prefixes for VRChat and Deadlock
# This fixes common launch issues caused by corrupted Wine prefixes

echo "=== Steam Proton Prefix Reset Tool ==="
echo ""

# App IDs
VRCHAT_APPID="438100"
DEADLOCK_APPID="1422450"
STEAM_APPS="$HOME/.local/share/Steam/steamapps"

echo "This script will reset Proton prefixes for:"
echo "  - VRChat (AppID: $VRCHAT_APPID)"
echo "  - Deadlock (AppID: $DEADLOCK_APPID)"
echo ""
echo "WARNING: This will delete game save data stored in the prefix!"
echo "Most games use Steam Cloud saves, but some local saves may be lost."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Closing Steam..."
killall steam 2>/dev/null
sleep 3

# Function to reset prefix
reset_prefix() {
    local appid=$1
    local name=$2
    local prefix_path="$STEAM_APPS/compatdata/$appid"
    
    echo ""
    echo "Processing $name (AppID: $appid)..."
    
    if [[ -d "$prefix_path" ]]; then
        echo "  Found prefix at: $prefix_path"
        echo "  Backing up to: $prefix_path.backup.$(date +%Y%m%d%H%M%S)"
        mv "$prefix_path" "$prefix_path.backup.$(date +%Y%m%d%H%M%S)"
        echo "  ✓ Prefix moved (backup created)"
    else
        echo "  No existing prefix found (this is OK)"
    fi
    
    echo "  ✓ $name ready for fresh Proton prefix creation"
}

# Reset VRChat
reset_prefix "$VRCHAT_APPID" "VRChat"

# Reset Deadlock  
reset_prefix "$DEADLOCK_APPID" "Deadlock"

echo ""
echo "=== Reset Complete ==="
echo ""
echo "Next steps:"
echo "1. Restart Steam"
echo "2. For VRChat: Set Proton to 'Proton-GE-RTSP' in game properties"
echo "3. For Deadlock: Set Proton to 'Proton Experimental' in game properties"
echo "4. Launch each game - Steam will create fresh Proton prefixes"
echo ""
echo "Note: First launch may take longer as Proton sets up the new prefix."
