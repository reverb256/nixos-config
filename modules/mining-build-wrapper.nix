# Mining-aware Build Wrapper with XMrig API Integration
# Pauses CPU mining before builds and resumes after completion
# XMrig exposes HTTP API on localhost:18088 for control

{pkgs, ...}:

  # Mining pause script
  mining-pause = pkgs.writeShellScriptBin "mining-pause" ''
    #!/bin/sh
    set -e

    XMRIG_API="http://127.0.0.1:18088"
    TIMEOUT=5

    # Pause mining
    echo "Pausing XMrig via API..."
    curl -s --max-time "$TIMEOUT" "$XMRIG_API/throttle" \
      -X PUT \
      -H "Content-Type: application/json" \
      -d '{"throttle": 0}' \
      || {
        echo "Warning: Failed to pause XMrig (API not responding)"
        echo "Attempting fallback: sending SIGSTOP to xmrig process..."
        pkill -STOP xmrig || true
      }

    if [ $? -eq 0 ]; then
      echo "✓ XMirig paused successfully"
    fi
  '';

  # Mining resume script
  mining-resume = pkgs.writeShellScriptBin "mining-resume" ''
    #!/bin/sh
    set -e

    XMRIG_API="http://127.0.0.1:18088"
    TIMEOUT=5

    # Resume mining to 50% CPU
    echo "Resuming XMrig via API to 50% throttle..."
    curl -s --max-time "$TIMEOUT" "$XMRIG_API/throttle" \
      -X PUT \
      -H "Content-Type: application/json" \
      -d '{"throttle": 50}' \
      || {
        echo "Warning: Failed to resume XMrig (API not responding)"
        echo "Attempting fallback: sending SIGCONT to xmrig process..."
        pkill -CONT xmrig || true
      }

    if [ $? -eq 0 ]; then
      echo "✓ XMrig resumed to 50% throttle"
    fi
  '';

  # Build wrapper script
  build-wrapper = pkgs.writeShellScriptBin "build-wrapper" ''
    #!/bin/sh
    set -e

    # Pause mining before building
    echo "========================================="
    echo "  BUILD STARTED"
    echo "========================================="
    echo "Pausing mining..."
    "$0/mining-pause" || true

    # Run the actual build command
    echo "Running build: $@"
    "$@"

    BUILD_STATUS=$?

    echo ""
    echo "========================================="
    echo "  BUILD COMPLETE (status: $BUILD_STATUS)"
    echo "========================================="
    echo "Resuming mining to 50% throttle..."
    "$0/mining-resume" || true
    echo "✓ Mining resumed"
  '';
}
