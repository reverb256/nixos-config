{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.mining-inference-coordinator;
in {
  options.services.mining-inference-coordinator = {
    enable = lib.mkEnableOption "Mining-Inference Coordinator";

    llamaPort = lib.mkOption {
      type = lib.types.port;
      default = 1237; # 3090 llama.cpp server port
      description = "Port the llama-server is listening on (3090 moved to 1237)";
    };

    comfyuiPort = lib.mkOption {
      type = lib.types.port;
      default = 8188;
      description = "Port ComfyUI is listening on (3090 GPU)";
    };

    primaryMiner = lib.mkOption {
      type = lib.types.str;
      default = "peakminer-zephyr-3090.service";
      description = "systemd unit for the primary miner (3090). The K8s deployment is gone -- peakminer runs as a systemd service now.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "mining";
      description = "DEPRECATED: K8s namespace option. Coordinator no longer scales K8s deployments -- kept for backwards compat with existing host configs that still set this.";
    };

    checkInterval = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "How often to check inference status (seconds)";
    };

    idleTimeout = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Seconds of no inference before resuming primary mining";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.mining-inference-coordinator = {
      description = "Mining-Inference Coordinator - Pauses 3090 mining during inference";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      # kubectl dropped: coordinator now drives systemd only (peakminer-zephyr-3090.service).
      # systemctl is available via /run/current-system/sw/bin/systemctl on NixOS.
      path = with pkgs; [curl gawk];

      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeShellScript "mining-inference-coordinator" ''
          set -uo pipefail

          LLAMA_PORT="${toString cfg.llamaPort}"
          COMFYUI_PORT="${toString cfg.comfyuiPort}"
          PRIMARY="${cfg.primaryMiner}"
          # NS was used by the old kubectl-based path; the systemd path doesn't need a namespace.
          CHECK_INTERVAL="${toString cfg.checkInterval}"
          IDLE_TIMEOUT="${toString cfg.idleTimeout}"

          last_tokens_predicted=-1
          inference_source="unknown"
          last_inference_time=0
          mining_shifted=false

          log() {
            echo "[$(date '+%H:%M:%S')] $*" >&2
          }

          scale() {
            local resource="$1"
            local target_state="$2"
            if [ "$target_state" = "0" ]; then
              systemctl stop "$resource" 2>/dev/null || true
            else
              systemctl start "$resource" 2>/dev/null || true
            fi
          }

          is_inference_active() {
            local processing
            processing=$(curl -sf "http://127.0.0.1:$LLAMA_PORT/metrics" 2>/dev/null \
              | grep "^llamacpp:requests_processing " \
              | awk '{print $2}')

            if [ -n "$processing" ] && [ "$processing" -gt 0 ]; then
              return 0
            fi

            local current_tokens
            current_tokens=$(curl -sf "http://127.0.0.1:$LLAMA_PORT/metrics" 2>/dev/null \
              | grep "^llamacpp:tokens_predicted_total " \
              | awk '{print $2}')

            if [ -n "$current_tokens" ] && [ "$last_tokens_predicted" -ge 0 ]; then
              if [ "$current_tokens" -gt "$last_tokens_predicted" ]; then
                last_tokens_predicted=$current_tokens
                return 0
              fi
            fi

            if [ -n "$current_tokens" ]; then
              last_tokens_predicted=$current_tokens
            fi

            return 1
          }

          is_comfyui_active() {
            local queue_response
            queue_response=$(curl -sf "http://127.0.0.1:$COMFYUI_PORT/queue" 2>/dev/null)

            # ComfyUI not running or unreachable
            if [ -z "$queue_response" ]; then
              return 1
            fi

            # Running jobs = GPU actively working
            # Pending jobs = GPU will be used next
            # Both should pause mining
            echo "$queue_response" | grep -qE '"queue_running":\s*\[[^]]' && return 0
            echo "$queue_response" | grep -qE '"queue_pending":\s*\[[^]]' && return 0

            return 1
          }

          any_inference_active() {
            inference_source="unknown"
            if is_inference_active; then
              inference_source="llama-server"
              return 0
            fi
            if is_comfyui_active; then
              inference_source="ComfyUI"
              return 0
            fi
            return 1
          }

          shift_to_fallback() {
            local source="''${1:-inference}"
            scale "$PRIMARY" 0
            mining_shifted=true
            log "PAUSED: 3090 miner stopped ($source)"
          }

          shift_to_primary() {
            scale "$PRIMARY" 1
            mining_shifted=false
            log "RESUMED: 3090 -> mining"
          }

          log "Coordinator started - monitoring :$LLAMA_PORT (llama-server), :$COMFYUI_PORT (ComfyUI)"
          log "Primary: $PRIMARY (3090)"
          log "Check interval: ''${CHECK_INTERVAL}s, idle timeout: ''${IDLE_TIMEOUT}s"

          while true; do
            current_time=$(date +%s)

            if any_inference_active; then
              last_inference_time=$current_time

              if [ "$mining_shifted" = false ]; then
                shift_to_fallback "$inference_source"
              fi
            else
              if [ "$mining_shifted" = true ] && [ "$last_inference_time" -gt 0 ]; then
                idle_time=$((current_time - last_inference_time))

                if [ "$idle_time" -ge "$IDLE_TIMEOUT" ]; then
                  shift_to_primary
                fi
              fi
            fi

            sleep "$CHECK_INTERVAL"
          done
        '';
        Restart = "always";
        RestartSec = 5;
      };
    };
  };
}
