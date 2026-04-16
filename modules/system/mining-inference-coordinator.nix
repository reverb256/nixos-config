{ config, lib, pkgs, ... }:

let
  cfg = config.services.mining-inference-coordinator;
in
{
  options.services.mining-inference-coordinator = {
    enable = lib.mkEnableOption "Mining-Inference Coordinator";

    llamaPort = lib.mkOption {
      type = lib.types.port;
      default = 1235;
      description = "Port the llama-server is listening on";
    };

    miningService = lib.mkOption {
      type = lib.types.str;
      default = "lolminer-nvidia.service";
      description = "Systemd service name for the GPU miner";
    };

    checkInterval = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "How often to check inference status (seconds)";
    };

    idleTimeout = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Seconds of no inference before resuming mining";
    };

    cooldownTimeout = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Seconds to wait after resuming mining before accepting new inference pauses";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.mining-inference-coordinator = {
      description = "Mining-Inference Coordinator - Pauses GPU mining during LLM inference";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [ curl gawk systemd ];

      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeShellScript "mining-inference-coordinator" ''
          set -uo pipefail

          LLAMA_PORT="${toString cfg.llamaPort}"
          MINING_SERVICE="${cfg.miningService}"
          CHECK_INTERVAL="${toString cfg.checkInterval}"
          IDLE_TIMEOUT="${toString cfg.idleTimeout}"

          # Track last known tokens to detect NEW activity (not cumulative)
          last_tokens_predicted=-1
          last_inference_time=0
          mining_paused=false
          cooldown_until=0

          log() {
            echo "[$(date '+%H:%M:%S')] $*" >&2
          }

          is_inference_active() {
            # Use requests_processing gauge — 0 = idle, >0 = active
            local processing
            processing=$(curl -sf "http://127.0.0.1:$LLAMA_PORT/metrics" 2>/dev/null \
              | grep "^llamacpp:requests_processing " \
              | awk '{print $2}')

            if [ -n "$processing" ] && [ "$processing" -gt 0 ]; then
              return 0  # active
            fi

            # Fallback: check if tokens_predicted counter is still climbing
            local current_tokens
            current_tokens=$(curl -sf "http://127.0.0.1:$LLAMA_PORT/metrics" 2>/dev/null \
              | grep "^llamacpp:tokens_predicted_total " \
              | awk '{print $2}')

            if [ -n "$current_tokens" ] && [ "$last_tokens_predicted" -ge 0 ]; then
              if [ "$current_tokens" -gt "$last_tokens_predicted" ]; then
                last_tokens_predicted=$current_tokens
                return 0  # still generating
              fi
            fi

            if [ -n "$current_tokens" ]; then
              last_tokens_predicted=$current_tokens
            fi

            return 1  # idle
          }

          pause_mining() {
            systemctl stop "$MINING_SERVICE" 2>/dev/null || true
            # Also scale down any K8s GPU mining pods on this node
            ${pkgs.kubectl}/bin/kubectl scale deployment gpu-miner-zephyr --replicas=0 -n mining 2>/dev/null || true
            mining_paused=true
            log "Mining PAUSED — inference in progress"
          }

          resume_mining() {
            systemctl start "$MINING_SERVICE" 2>/dev/null || true
            ${pkgs.kubectl}/bin/kubectl scale deployment gpu-miner-zephyr --replicas=1 -n mining 2>/dev/null || true
            mining_paused=false
            cooldown_until=$(($(date +%s) + ${toString cfg.cooldownTimeout}))
            log "Mining RESUMED — inference idle for $1s"
          }

          log "Coordinator started — monitoring :$LLAMA_PORT, controlling $MINING_SERVICE"
          log "Check interval: ''${CHECK_INTERVAL}s, idle timeout: ''${IDLE_TIMEOUT}s"

          while true; do
            current_time=$(date +%s)

            if is_inference_active; then
              last_inference_time=$current_time

              if [ "$mining_paused" = false ] && [ "$current_time" -ge "$cooldown_until" ]; then
                pause_mining
              fi
            else
              if [ "$mining_paused" = true ] && [ "$last_inference_time" -gt 0 ]; then
                idle_time=$((current_time - last_inference_time))

                if [ "$idle_time" -ge "$IDLE_TIMEOUT" ]; then
                  resume_mining "$idle_time"
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
