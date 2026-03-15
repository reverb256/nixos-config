# XMRig HTTP API Control Module
# Provides helper functions for pause/resume/thread control via HTTP API
{ config, lib, pkgs, ... }:

let
  cfg = config.services.mining.xmrig;

in {
  config = lib.mkIf config.services.compute-workload-monitor.enable {
    # Create a helper script for XMRig API control
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "xmrig-api-control" ''
        # XMRig HTTP API Control Helper
        # Usage: xmrig-api-control {pause|resume|status|threads <count>} [instance]
        #   instance: "always" (default) or "flexible"

        # Default to always-on instance if not specified
        XMRIG_INSTANCE="''${1:-always}"
        shift 2>/dev/null || true

        case "$XMRIG_INSTANCE" in
            always|flexible)
                INSTANCE="$XMRIG_INSTANCE"
                ;;
            pause|resume|status|threads)
                # Old syntax: command first, then instance
                INSTANCE="always"
                set -- "$XMRIG_INSTANCE" ''${@}
                ;;
            *)
                echo "Unknown instance: $XMRIG_INSTANCE" >&2
                echo "Valid instances: always, flexible" >&2
                exit 1
                ;;
        esac

        # Configure based on instance
        case "$INSTANCE" in
            always)
                XMRIG_API_PORT="8081"
                XMRIG_API_TOKEN_FILE="/run/agenix/xmrig-always-api-token"
                XMRIG_SERVICE="xmrig-always"
                ;;
            flexible)
                XMRIG_API_PORT="8082"
                XMRIG_API_TOKEN_FILE="/run/agenix/xmrig-flexible-api-token"
                XMRIG_SERVICE="xmrig-flexible"
                ;;
        esac

        XMRIG_API_HOST="127.0.0.1"

        log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
        }

        # Call XMRig API with authentication
        xmrig_api() {
            local endpoint="$1"
            local data="$2"

            if [ ! -r "$XMRIG_API_TOKEN_FILE" ]; then
                log "WARNING: XMRig API token file not found: $XMRIG_API_TOKEN_FILE"
                return 1
            fi

            local token=$(cat "$XMRIG_API_TOKEN_FILE" 2>/dev/null)
            if [ -z "$token" ]; then
                log "WARNING: XMRig API token is empty"
                return 1
            fi

            local url="http://''${XMRIG_API_HOST}:''${XMRIG_API_PORT}''${endpoint}"
            local response
            response=$(curl -s -X POST "$url" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                -d "$data" \
                -w "%{http_code}" -o /tmp/xmrig_api_response.json 2>/dev/null)

            local http_code="$response"
            local body=$(cat /tmp/xmrig_api_response.json 2>/dev/null || echo "{}")
            rm -f /tmp/xmrig_api_response.json

            if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
                log "XMRig API success: $endpoint -> $http_code"
                return 0
            else
                log "XMRig API error: $endpoint -> $http_code: $body"
                return 1
            fi
        }

        # Get current XMRig status (paused or running)
        xmrig_status() {
            if [ ! -r "$XMRIG_API_TOKEN_FILE" ]; then
                echo "unknown"
                return 1
            fi

            local token=$(cat "$XMRIG_API_TOKEN_FILE" 2>/dev/null)
            if [ -z "$token" ]; then
                echo "unknown"
                return 1
            fi

            local url="http://''${XMRIG_API_HOST}:''${XMRIG_API_PORT}/1/summary"
            local status
            status=$(curl -s -X GET "$url" \
                -H "Authorization: Bearer $token" 2>/dev/null)

            if echo "$status" | grep -q '"paused".*true'; then
                echo "paused"
            elif echo "$status" | grep -q '"paused".*false'; then
                echo "running"
            else
                echo "unknown"
            fi
        }

        # Main command handling
        COMMAND="$1"
        shift 2>/dev/null || true

        case "$COMMAND" in
            pause)
                if systemctl is-active --quiet "$XMRIG_SERVICE"; then
                    # XMRig v2 API: use /2/control with pause command
                    xmrig_api "/2/control" "{\"command\":\"pause\"}" && echo "XMRig [$INSTANCE] paused" || echo "Failed to pause [$INSTANCE]"
                else
                    echo "XMRig [$INSTANCE] not running"
                fi
                ;;
            resume)
                if systemctl is-active --quiet "$XMRIG_SERVICE"; then
                    # XMRig v2 API: use /2/control with resume command
                    xmrig_api "/2/control" "{\"command\":\"resume\"}" && echo "XMRig [$INSTANCE] resumed" || echo "Failed to resume [$INSTANCE]"
                else
                    echo "XMRig [$INSTANCE] not running, starting..."
                    systemctl start "$XMRIG_SERVICE"
                fi
                ;;
            status)
                xmrig_status
                ;;
            threads)
                if [ -z "$1" ]; then
                    echo "Usage: $0 threads <count> [instance]"
                    exit 1
                fi
                if systemctl is-active --quiet "$XMRIG_SERVICE"; then
                    # XMRig v1 API: use /1/threads to set thread count
                    xmrig_api "/1/threads" "{\"threads_count\": $1}" && echo "XMRig [$INSTANCE] threads set to $1" || echo "Failed to set threads [$INSTANCE]"
                else
                    echo "XMRig [$INSTANCE] not running"
                fi
                ;;
            *)
                echo "Usage: $0 {pause|resume|status|threads <count>} [instance]"
                echo "  instance: always (default) or flexible"
                exit 1
                ;;
        esac
      '')
    ];

    # Create runtime directory for API control
    systemd.tmpfiles.rules = [
      "d /run/xmrig-api 0755 root root - -"
    ];
  };
}
