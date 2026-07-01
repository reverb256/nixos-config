{ config, lib, pkgs, ... }: let
  cfg = config.services.k8s-secrets-sync;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.k8s-secrets-sync = {
    enable = mkEnableOption "Sync K8s secrets from sops-nix runtime paths";
  };

  config = mkIf cfg.enable {
    systemd.services.k8s-secrets-sync = {
      description = "Sync K8s secrets from /run/secrets to Kubernetes";
      after = ["k3s.service" "sops-nix.service"];
      bindsTo = ["k3s.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        Environment = "KUBECONFIG=/home/j_kro/.kube/config";
        RemainAfterExit = true;
      };
      path = [pkgs.kubectl pkgs.coreutils];
      script = ''
        set -euo pipefail

        echo "[k8s-secrets-sync] K3s is active. Syncing secrets..."

        # Sync HF token
        if [ -f /run/secrets/huggingface-token ]; then
          HF_TOKEN=$(cat /run/secrets/huggingface-token)
          kubectl --insecure-skip-tls-verify=true --validate=false create secret generic hf-token -n ai-inference \
            --from-literal=token="$HF_TOKEN" \
            --dry-run=client -o yaml | kubectl --insecure-skip-tls-verify=true apply -f -
          echo "[k8s-secrets-sync] Synced hf-token to ai-inference namespace"
        else
          echo "[k8s-secrets-sync] Warning: huggingface-token not found"
        fi

        # Sync ZAI API key
        if [ -f /run/secrets/ai-gateway-zai-api-key ]; then
          ZAI_KEY=$(cat /run/secrets/ai-gateway-zai-api-key)
          kubectl --insecure-skip-tls-verify=true --validate=false create secret generic zai-api-key -n ai-inference \
            --from-literal=ZAI_API_KEY="$ZAI_KEY" \
            --dry-run=client -o yaml | kubectl --insecure-skip-tls-verify=true apply -f -
          echo "[k8s-secrets-sync] Synced zai-api-key to ai-inference namespace"
        fi

        # Sync NVIDIA API key
        if [ -f /run/secrets/nvidia-api-key ]; then
          NVIDIA_KEY=$(cat /run/secrets/nvidia-api-key)
          kubectl --insecure-skip-tls-verify=true --validate=false create secret generic nvidia-api-key -n ai-inference \
            --from-literal=NVIDIA_API_KEY="$NVIDIA_KEY" \
            --dry-run=client -o yaml | kubectl --insecure-skip-tls-verify=true apply -f -
          echo "[k8s-secrets-sync] Synced nvidia-api-key to ai-inference namespace"
        fi

        # Sync KILO API key
        if [ -f /run/secrets/kilo-api-key ]; then
          KILO_KEY=$(cat /run/secrets/kilo-api-key)
          kubectl --insecure-skip-tls-verify=true --validate=false create secret generic kilo-api-key -n ai-inference \
            --from-literal=KILO_API_KEY="$KILO_KEY" \
            --dry-run=client -o yaml | kubectl --insecure-skip-tls-verify=true apply -f -
          echo "[k8s-secrets-sync] Synced kilo-api-key to ai-inference namespace"
        fi

        # Sync OpenCode API key
        if [ -f /run/secrets/opencode-api-key ]; then
          OPENCODE_KEY=$(cat /run/secrets/opencode-api-key)
          kubectl --insecure-skip-tls-verify=true --validate=false create secret generic opencode-api-key -n ai-inference \
            --from-literal=OPENCODE_API_KEY="$OPENCODE_KEY" \
            --dry-run=client -o yaml | kubectl --insecure-skip-tls-verify=true apply -f -
          echo "[k8s-secrets-sync] Synced opencode-api-key to ai-inference namespace"
        fi

        # Sync AI Gateway token
        if [ -f /run/secrets/hermes-env ]; then
          GATEWAY_TOKEN=$(cat /run/secrets/hermes-env)
          kubectl --insecure-skip-tls-verify=true --validate=false create secret generic ai-gateway-token -n ai-inference \
            --from-literal=GATEWAY_TOKEN="$GATEWAY_TOKEN" \
            --dry-run=client -o yaml | kubectl --insecure-skip-tls-verify=true apply -f -
          echo "[k8s-secrets-sync] Synced ai-gateway-token to ai-inference namespace"
        fi

        echo "[k8s-secrets-sync] Done."
      '';
    };
  };
}