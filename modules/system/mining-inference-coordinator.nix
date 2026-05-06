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

    primaryMiner = lib.mkOption {
      type = lib.types.str;
      default = "deployment/gpu-miner-zephyr";
      description = "K8s resource for the primary miner (3090)";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "mining";
      description = "K8s namespace for mining resources";
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

      path = with pkgs; [curl gawk kubectl];

      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeShellScript "mining-inference-coordinator" ''
          set -uo pipefail

          LLAMA_PORT="${toString cfg.llamaPort}"
          PRIMARY="${cfg.primaryMiner}"
          FALLBACK="${cfg.fallbackMiner}"
          NS="${cfg.namespace}"
          CHECK_INTERVAL="${toString cfg.checkInterval}"
          IDLE_TIMEOUT="${toString cfg.idleTimeout}"

          last_tokens_predicted=-1
          last_inference_time=0
          mining_shifted=false

          log() {
            echo "[$(date '+%H:%M:%S')] $*" >&2
          }

          scale() {
            local resource="$1"
            local replicas="$2"
            kubectl scale "$resource" --replicas="$replicas" -n "$NS" 2>/dev/null || true
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

          shift_to_fallback() {
            scale "$PRIMARY" 0
            mining_shifted=true
            log "PAUSED: 3090 miner stopped for inference"
          }

          shift_to_primary() {
            scale "$PRIMARY" 1
            mining_shifted=false
            log "RESUMED: 3090 -> mining"
          }

          log "Coordinator started - monitoring :$LLAMA_PORT"
          log "Primary: $PRIMARY (3090) | Fallback: ''${FALLBACK:-none}"
          log "Check interval: ''${CHECK_INTERVAL}s, idle timeout: ''${IDLE_TIMEOUT}s"

          while true; do
            current_time=$(date +%s)

            if is_inference_active; then
              last_inference_time=$current_time

              if [ "$mining_shifted" = false ]; then
                shift_to_fallback
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
