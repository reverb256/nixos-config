{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.services.mining-coordinator.enable or false) {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "xmrig-api-control" ''

        XMRIG_INSTANCE="''${1:-always}"
        shift 2>/dev/null || true

        case "$XMRIG_INSTANCE" in
            always|flexible)
                INSTANCE="$XMRIG_INSTANCE"
                ;;
            pause|resume|status|threads)
                INSTANCE="always"
                set -- "$XMRIG_INSTANCE" ''${@}
                ;;
            *)
                echo "Unknown instance: $XMRIG_INSTANCE" >&2
                echo "Valid instances: always, flexible" >&2
                exit 1
                ;;
        esac

        case "$INSTANCE" in
            always)
                XMRIG_API_PORT="8081"
                XMRIG_API_TOKEN_FILE="/run/secrets/xmrig-always-api-token"
                XMRIG_SERVICE="xmrig-always"
                ;;
            flexible)
                XMRIG_API_PORT="8082"
                XMRIG_API_TOKEN_FILE="/run/secrets/xmrig-flexible-api-token"
                XMRIG_SERVICE="xmrig-flexible"
                ;;
        esac

        XMRIG_API_HOST="127.0.0.1"

        log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
        }

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

        COMMAND="$1"
        shift 2>/dev/null || true

        case "$COMMAND" in
            pause)
                if systemctl is-active --quiet "$XMRIG_SERVICE"; then
                    xmrig_api "/2/control" "{\"command\":\"pause\"}" && echo "XMRig [$INSTANCE] paused" || echo "Failed to pause [$INSTANCE]"
                else
                    echo "XMRig [$INSTANCE] not running"
                fi
                ;;
            resume)
                if systemctl is-active --quiet "$XMRIG_SERVICE"; then
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

    systemd.tmpfiles.rules = [
      "d /run/xmrig-api 0755 root root - -"
    ];
  };
}
