#!/usr/bin/env bash
# Setup Easy Audio Mode Switching
# Creates desktop entries, keyboard shortcuts, and auto-switching

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
info() { echo -e "${CYAN}[SETUP]${NC} $1"; }

echo ""
echo "╔═════════════════════════════════════════════════════╗"
echo "║     Easy Audio Switching Setup                     ║"
echo "╚═════════════════════════════════════════════════════╝"
echo ""

# Create desktop entries directory
mkdir -p ~/.local/share/applications

info "Creating desktop entries..."

# PC Mode
cat > ~/.local/share/applications/audio-pc.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=🖥️ PC Audio
Comment=Switch to desk speakers
Icon=audio-card
Exec=/etc/nixos/docs/audio-profiles.sh pc
Terminal=false
Categories=Audio;AudioVideo;
StartupNotify=false
EOF

# TV Mode
cat > ~/.local/share/applications/audio-tv.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=📺 TV Audio
Comment=Switch to TV speakers
Icon=video-display
Exec=/etc/nixos/docs/audio-profiles.sh tv
Terminal=false
Categories=Audio;AudioVideo;
StartupNotify=false
EOF

log "✅ Desktop entries created"

# Create fish aliases
info "Creating fish shell aliases..."

FISH_CONFIG="$HOME/.config/fish/config.fish"

if ! grep -q "audio-pc" "$FISH_CONFIG" 2>/dev/null; then
  cat >> "$FISH_CONFIG" << 'EOF'

# Audio mode switching
alias audio-pc="/etc/nixos/docs/audio-profiles.sh pc"
alias audio-tv="/etc/nixos/docs/audio-profiles.sh tv"
alias audio-both="/etc/nixos/docs/audio-profiles.sh pc+tv"
alias audio-status="/etc/nixos/docs/audio-profiles.sh status"
EOF
  log "✅ Fish aliases added"
else
  log "ℹ️  Fish aliases already exist"
fi

echo ""
log "✅ Easy switching setup complete!"
echo ""
echo "════════════════════════════════════════════════════"
log "Now You Can Switch Audio Using:"
echo "════════════════════════════════════════════════════"
echo ""
echo "1️⃣  Application Launcher (easiest)"
echo "   Press Meta/Alt + F1 (or your launcher key)"
echo "   Type: 'PC Audio' or 'TV Audio'"
echo "   Press Enter"
echo ""
echo "2️⃣  Terminal (fastest)"
echo "   audio-pc      # Desk speakers"
echo "   audio-tv      # TV speakers"
echo "   audio-both    # Both outputs"
echo "   audio-status  # Check mode"
echo ""
echo "3️⃣  Direct command"
echo "   /etc/nixos/docs/audio-profiles.sh pc"
echo ""
echo "════════════════════════════════════════════════════"
echo ""
