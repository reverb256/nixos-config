# Mining-aware Build Wrapper with XMrig API Integration
# Pauses CPU mining before builds and resumes after completion
# XMrig exposes HTTP API on localhost:18088 for control
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.mining-build-wrapper;
in {
  options.mining-build-wrapper = {
    enable = lib.mkEnableOption "Mining-aware build wrapper";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "mining-pause" ''
        #!/bin/sh
        set -e

        XMRIG_API="http://127.0.0.1:18088"
        TIMEOUT=5

        # Pause mining
        echo "Pausing XMrig via API..."
        ${curl}/bin/curl -s --max-time "$TIMEOUT" "$XMRIG_API/throttle" \
          -X PUT \
          -H "Content-Type: application/json" \
          -d '{"throttle": 0}' \
          || {
            echo "Warning: Failed to pause XMrig (API not responding)"
            echo "Attempting fallback: sending SIGSTOP to xmrig process..."
            ${procps}/bin/pkill -STOP xmrig || true
          }

        if [ $? -eq 0 ]; then
          echo "✓ XMrig paused successfully"
        fi
      '')

      (writeShellScriptBin "mining-resume" ''
        #!/bin/sh
        set -e

        XMRIG_API="http://127.0.0.1:18088"
        TIMEOUT=5

        # Resume mining to 50% CPU
        echo "Resuming XMrig via API to 50% throttle..."
        ${curl}/bin/curl -s --max-time "$TIMEOUT" "$XMRIG_API/throttle" \
          -X PUT \
          -H "Content-Type: application/json" \
          -d '{"throttle": 50}' \
          || {
            echo "Warning: Failed to resume XMrig (API not responding)"
            echo "Attempting fallback: sending SIGCONT to xmrig process..."
            ${procps}/bin/pkill -CONT xmrig || true
          }

        if [ $? -eq 0 ]; then
          echo "✓ XMrig resumed to 50% throttle"
        fi
      '')

      (writeShellScriptBin "build-wrapper" ''
        #!/bin/sh
        set -e

        # Pause mining before building
        echo "========================================="
        echo "  BUILD STARTED"
        echo "========================================="
        echo "Pausing mining..."
        ${pkgs.mining-pause}/bin/mining-pause || true

        # Run actual build command
        echo "Running build: $@"
        "$@"

        BUILD_STATUS=$?

        echo ""
        echo "========================================="
        echo "  BUILD COMPLETE (status: $BUILD_STATUS)"
        echo "========================================="
        echo "Resuming mining to 50% throttle..."
        ${pkgs.mining-resume}/bin/mining-resume || true
        echo "✓ Mining resumed"
      '')
    ];
  };
}
