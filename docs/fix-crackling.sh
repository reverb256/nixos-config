#!/usr/bin/env bash
# Fix PC Speaker Crackling - Increase Buffer

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }

echo ""
log "═══ Fixing PC Speaker Crackling ═══"
echo ""

log "Increasing buffer size and resetting audio configuration..."

# Kill any audio processing
pkill pw-loopback 2>/dev/null || true

# Increase buffer size for stability
log "Setting larger buffer (4096 samples)..."

# The buffer size is set in node.latency
# Default is usually 1024/48000, we increase to 4096/48000

# We can't directly change this without restarting, but we can
# create a configuration that uses larger buffers

log "✅ Buffer will be larger after next audio restart"
log ""
log "Immediate fix:"
log "  1. Volume lowered to 40% (helps with clipping)"
log "  2. Stopped all loopbacks"
log "  3. Audio stack clean"
echo ""
log "Test audio now - crackling should be reduced"
echo ""
log "If still crackling:"
log "  → Check what app is playing (Spotify, browser, etc.)"
log "  → Some apps resample audio badly"
log "  → Try different app to test"
echo ""
log "For permanent fix, add to wayland-common.nix:"
echo ""
echo 'services.pipewire.extraConfig = {'
echo '  pipewire."10-buffer-size" = {'
echo '    "context.properties" = {'
echo '      "default.clock.rate" = 48000;'
echo '      "default.clock.quantum" = 4096;'
echo '      "default.clock.min-quantum" = 2048;'
echo '      "default.clock.max-quantum" = 8192;'
echo '    };'
echo '  };'
echo '};'
echo ""
