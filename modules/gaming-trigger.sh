#!/bin/bash

set -e

GAMING_SERVICE="gaming-optimizations.service"
DETECTOR_SERVICE="game-detector.service"

case "$1" in
  "start")
    echo "Starting universal gaming optimizations..."
    sudo systemctl start "$GAMING_SERVICE"
    echo "✓ Gaming optimizations enabled"
    ;;
  
  "stop")
    echo "Stopping universal gaming optimizations..."
    sudo systemctl stop "$GAMING_SERVICE"
    echo "✓ Gaming optimizations disabled"
    ;;
  
  "status")
    echo "=== Gaming Optimization Status ==="
    echo "Detector Service: $(systemctl is-active "$DETECTOR_SERVICE")"
    echo "Optimizations Service: $(systemctl is-active "$GAMING_SERVICE")"
    echo ""
    echo "=== Current Game Detection State ==="
    if pgrep -f "steam.*game|valve.*source|vulkan.*render|dxgi.*render|wine.*exe|gamemode" > /dev/null; then
      echo "✓ Games detected (process-based)"
    else
      echo "✗ No games detected (process-based)"
    fi
    
    if nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | awk '{if($1 > 70) exit 0; exit 1}'; then
      echo "✓ High GPU usage detected (>70%)"
    else
      echo "✗ GPU usage normal"
    fi
    
    if pgrep -f "wivrn|steamvr|vrserver|vulkaninfo" > /dev/null; then
      echo "✓ VR applications detected"
    else
      echo "✗ No VR applications detected"
    fi
    ;;
  
  "monitor")
    echo "Monitoring gaming state (press Ctrl+C to stop)..."
    while true; do
      echo -n "$(date '+%H:%M:%S') - Gaming state: "
      if systemctl is-active "$GAMING_SERVICE" &>/dev/null; then
        echo "ACTIVE"
      else
        echo "INACTIVE"
      fi
      sleep 2
    done
    ;;
  
  *)
    echo "Usage: $0 [start|stop|status|monitor]"
    echo ""
    echo "Commands:"
    echo "  start   - Manually enable gaming optimizations"
    echo "  stop    - Manually disable gaming optimizations" 
    echo "  status  - Show current optimization status and game detection"
    echo "  monitor - Continuously monitor gaming state"
    echo ""
    echo "Automatic detection is handled by game-detector.service"
    exit 1
    ;;
esac