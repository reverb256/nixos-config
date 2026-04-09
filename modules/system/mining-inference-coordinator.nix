{ config, lib, pkgs, ... }:
{
  systemd.services.mining-inference-coordinator = {
    description = "Mining-Inference Coordinator - Pauses mining during LLM inference";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "j_kro";
      ExecStart = pkgs.writeShellScript "mining-inference-coordinator" ''
        #!/bin/sh
        set -e

        LLAMA_HOST="10.1.1.110"
        LLAMA_PORT="8083"
        MINING_DEPLOYMENT="gpu-miner-zephyr"
        MINING_NAMESPACE="mining"
        CHECK_INTERVAL=5
        IDLE_TIMEOUT=60

        echo "🤖 Mining-Inference Coordinator Starting..."
        echo "📡 Monitoring: llama.cpp @ $LLAMA_HOST:$LLAMA_PORT"
        echo "⛏️  Mining deployment: $MINING_DEPLOYMENT"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        last_inference_time=0
        mining_paused=false

        while true; do
          if curl -s "http://$LLAMA_HOST:$LLAMA_PORT/metrics" 2>/dev/null | grep -q "llamacpp:tokens_predicted_total"; then
            # Get tokens generated (indicates active inference)
            tokens_predicted=$(curl -s "http://$LLAMA_HOST:$LLAMA_PORT/metrics" 2>/dev/null | \
              grep "llamacpp:tokens_predicted_total" | awk '{print $2}')

            current_time=$(date +%s)

            if [ "$tokens_predicted" -gt 0 ]; then
              last_inference_time=$current_time

              if [ "$mining_paused" = false ]; then
                echo "🧠 Inference active (tokens: $tokens_predicted), pausing mining..."
                ${pkgs.kubectl}/bin/kubectl scale deployment "$MINING_DEPLOYMENT" --replicas=0 -n "$MINING_NAMESPACE"
                mining_paused=true
                echo "✅ Mining paused"
              fi
            else
              if [ "$mining_paused" = true ]; then
                idle_time=$((current_time - last_inference_time))

                if [ "$idle_time" -gt "$IDLE_TIMEOUT" ]; then
                  echo "⛏️  Inference idle for ''${idle_time}s, resuming mining..."
                  ${pkgs.kubectl}/bin/kubectl scale deployment "$MINING_DEPLOYMENT" --replicas=1 -n "$MINING_NAMESPACE"
                  mining_paused=false
                  echo "✅ Mining resumed"
                fi
              fi
            fi
          fi

          sleep "$CHECK_INTERVAL"
        done
      '';
      Restart = "always";
      RestartSec = 10;
    };
  };
}
