#!/usr/bin/env bash
# Audio Sync Measurement Test
# Run this while standing midway between your two audio outputs

set -e

echo "╔═════════════════════════════════════════════════════╗"
echo "║     Audio Synchronization Test - Dual Output       ║"
echo "╚═════════════════════════════════════════════════════╝"
echo ""
echo "📋 Setup:"
echo "  1. Make sure both audio outputs are working"
echo "  2. Stand approximately midway between speakers"
echo "  3. The test will play 5 sharp clicks, 2 seconds apart"
echo ""
echo "🎯 What to listen for:"
echo "  - PERFECT SYNC: Single sharp click (sound from both)"
echo "  - HDMI DELAYED: You'll hear 'click-echo' (two distinct sounds)"
echo "  - ONBOARD DELAYED: You'll hear 'echo-click'"
echo ""
echo "⏱️  Count the milliseconds between the two sounds"
echo "   That's your latency offset value!"
echo ""
read -p "Press ENTER to start test..."

# Get PipeWire to play a sharp click
# Using a simple approach with system bell/beep
for i in {1..5}; do
  echo "Click $i of 5..."
  # Method 1: Try paplay if available
  if command -v paplay &> /dev/null; then
    paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || true
  fi

  # Method 2: Use speaker-test
  if command -v speaker-test &> /dev/null; then
    timeout 0.1 speaker-test -t sine -f 1000 -l 1 2>/dev/null || true
  fi

  # Method 3: Simple beep via console
  echo -en "\a" 2>/dev/null || true

  if [ $i -lt 5 ]; then
    sleep 2
  fi
done

echo ""
echo "═════════════════════════════════════════════════════"
echo "Test complete!"
echo ""
echo "📝 Based on what you heard:"
echo ""
echo "  ✅ Single click → Offset = 0ms (already synced!)"
echo ""
echo "  ⏱️  Echo AFTER click → HDMI is delayed"
echo "     If echo was ~50ms after: Set offset to 0.050"
echo "     If echo was ~30ms after: Set offset to 0.030"
echo ""
echo "  ⏱️  Echo BEFORE click → Onboard is delayed"
echo "     (less common, adjust negative offset)"
echo ""
echo "🔧 Apply your measured value in:"
echo "   /etc/nixos/modules/desktop/wayland-common.nix"
echo ""
echo "   Find this line:"
echo "   \"audio.latency.offset\" = \"0.050\";"
echo ""
echo "   Replace 0.050 with your measurement"
echo "═════════════════════════════════════════════════════"
