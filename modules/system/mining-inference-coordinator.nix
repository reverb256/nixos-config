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

    primaryMiner = lib.mkOption {
      type = lib.types.str;
      default = "lolminer-nvidia.service";
      description = "Main mining service (runs on the inference GPU, paused during inference)";
    };

    fallbackMiner = lib.mkOption {
      type = lib.types.str;
      default = "lolminer-3060ti.service";
      description = "Fallback mining service (started on secondary GPU during inference)";
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
    # Fallback miner: 3060 Ti only, 120W, stopped by default
    systemd.services.lolminer-3060ti = {
      description = "lolMiner NVIDIA 3060 Ti Fallback Mining Service";
      wantedBy = lib.mkForce []; # don't autostart
      after = [ "network.target" "lolminer-3060ti-power-limit.service" ];
      requires = [ "lolminer-3060ti-power-limit.service" ];
      serviceConfig = {
        Type = "simple";
        User = "j_kro";
        Group = "mining";
        Slice = "mining.slice";
        ExecStart = "${pkgs.lolminer}/bin/lolMiner --algo CR29 --pool stratum+tcp://10.1.1.120:3333 --user krxXVNVMM7.zephyr-gpu --pass x --tls off --devices 0 --apiport 4069 --mode b";
        Restart = "on-failure";
        RestartSec = "30s";
        Environment = [
          "GPU_MAX_HEAP_SIZE=100"
          "GPU_MAX_ALLOC_PERCENT=100"
        ];
        LimitMEMLOCK = "4G";
      };
    };

    # Set 3060 Ti power limit to 120W when mining
    systemd.services.lolminer-3060ti-power-limit = {
      description = "Set 3060 Ti power limit for mining";
      after = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "nvidia-smi -i 0 --power-limit 120";
        ExecStop = "nvidia-smi -i 0 --power-limit 0";
      };
    };

    systemd.services.mining-inference-coordinator = {
      description = "Mining-Inference Coordinator - Shifts mining to 3060 Ti during inference";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [ curl gawk systemd ];

      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeShellScript "mining-inference-coordinator" ''
          set -uo pipefail

          LLAMA_PORT="${toString cfg.llamaPort}"
          PRIMARY_MINER="${cfg.primaryMiner}"
          FALLBACK_MINER="${cfg.fallbackMiner}"
          CHECK_INTERVAL="${toString cfg.checkInterval}"
          IDLE_TIMEOUT="${toString cfg.idleTimeout}"

          last_tokens_predicted=-1
          last_inference_time=0
          mining_shifted=false

          log() {
            echo "[$(date '+%H:%M:%S')] $*" >&2
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
            # Stop 3090 mining, start 3060 Ti mining
            systemctl stop "$PRIMARY_MINER" 2>/dev/null || true
            systemctl start "$FALLBACK_MINER" 2>/dev/null || true
            mining_shifted=true
            log "SHIFTED: 3090 → inference | 3060 Ti → mining"
          }

          shift_to_primary() {
            # Stop 3060 Ti mining, start 3090 mining
            systemctl stop "$FALLBACK_MINER" 2>/dev/null || true
            systemctl start "$PRIMARY_MINER" 2>/dev/null || true
            mining_shifted=false
            log "SHIFTED: 3090 → mining | 3060 Ti → idle"
          }

          log "Coordinator started — monitoring :$LLAMA_PORT"
          log "Primary: $PRIMARY_MINER (3090) | Fallback: $FALLBACK_MINER (3060 Ti)"
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
                  shift_to_primary "$idle_time"
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
