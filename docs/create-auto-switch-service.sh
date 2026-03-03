#!/usr/bin/env bash
# Create systemd user service for auto-audio-switching

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/auto-audio-switch.service"

echo ""
echo "╔═════════════════════════════════════════════════════╗"
echo "║     Auto-Audio-Switch Service Setup                ║"
echo "╚═════════════════════════════════════════════════════╝"
echo ""

mkdir -p "$SERVICE_DIR"

log "Creating systemd service..."

cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Auto Audio Mode Switcher
After=pipewire.service
Wants=pipewire.service

[Service]
Type=simple
ExecStart=/etc/nixos/docs/auto-audio-config.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

log "✅ Service created"

# Reload systemd
systemctl --user daemon-reload 2>/dev/null || true

echo ""
log "════════════════════════════════════════════════════"
log "Service Commands"
log "════════════════════════════════════════════════════"
echo ""
echo "Enable auto-start on login:"
echo "  systemctl --user enable auto-audio-switch.service"
echo ""
echo "Start now:"
echo "  systemctl --user start auto-audio-switch.service"
echo ""
echo "Check status:"
echo "  systemctl --user status auto-audio-switch.service"
echo ""
echo "View logs:"
echo "  journalctl --user -u auto-audio-switch.service -f"
echo ""
echo "Stop auto-switching:"
echo "  systemctl --user stop auto-audio-switch.service"
echo ""
echo "Disable auto-start:"
echo "  systemctl --user disable auto-audio-switch.service"
echo ""
warn "NOTE: Before enabling, edit /etc/nixos/docs/auto-audio-config.sh"
warn "      to add your programs!"
echo ""
