{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf;
  pwsh = pkgs.writeShellScript "k8s-push-secrets" ''
    set -euo pipefail
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    echo "[k8s-secrets] Waiting for K8s API..."
    for _ in $(seq 1 60); do
      if kubectl get nodes >/dev/null 2>&1; then
        echo "[k8s-secrets] K8s API ready"
        break
      fi
      sleep 2
    done
    if ! kubectl get nodes >/dev/null 2>&1; then
      echo "[k8s-secrets] ERROR: K8s API not available after 120s"
      exit 1
    fi
    echo "[k8s-secrets] Applying sops-nix secrets to Kubernetes..."

    push_secret() {
      local ns=$1 name=$2 key=$3 file=$4
      if [ ! -f "$file" ]; then echo "[k8s-secrets] SKIP $ns/$name - $file not ready"; return 0; fi
      local val; val=$(cat "$file")
      if kubectl get secret "$name" -n "$ns" >/dev/null 2>&1; then
        kubectl patch secret "$name" -n "$ns" -p "{\"stringData\":{\"$key\":\"$val\"}}" 2>/dev/null && \
          echo "[k8s-secrets] OK $ns/$name ($key)" || \
          echo "[k8s-secrets] FAIL update $ns/$name"
      else
        kubectl create secret generic "$name" -n "$ns" --from-literal="$key=$val" --dry-run=client -o yaml | kubectl apply -f - && \
          echo "[k8s-secrets] OK $ns/$name (created)" || \
          echo "[k8s-secrets] FAIL create $ns/$name"
      fi
    }

    push_secret ai-inference zai-api-key ZAI_API_KEY /run/secrets/zai-api-key
    push_secret ai-inference hf-token TOKEN /run/secrets/huggingface-token
    push_secret ai-inference nvidia-api-key NVIDIA_API_KEY /run/secrets/nvidia-api-key
    push_secret ai-inference kilo-api-key KILO_API_KEY /run/secrets/kilo-api-key
    push_secret ai-inference opencode-api-key OPENCODE_API_KEY /run/secrets/opencode-api-key
    push_secret kelos-system opencode-credentials OPENCODE_API_KEY /run/secrets/opencode-api-key
    push_secret search searxng-secret secret-key /run/secrets/searxng-secret-key
    push_secret orchestration mission-control-secrets auth-pass /run/secrets/mission-control-auth-pass
    push_secret orchestration mission-control-secrets api-key /run/secrets/mission-control-api-key
    push_secret mining xmrig-proxy-secret api-token /run/secrets/xmrig-proxy-api-token
    push_secret monitoring grafana-admin-secret admin-password /run/secrets/grafana-admin-password
    push_secret monitoring grafana-oidc-secret client-secret /run/secrets/grafana-oidc-client-secret
    push_secret ai-inference openwebui-oidc-secret client-secret /run/secrets/openwebui-oidc-client-secret
    push_secret monitoring vaultwarden-oidc-secret client-secret /run/secrets/vaultwarden-oidc-client-secret
    push_secret automation n8n-secrets admin-password /run/secrets/n8n-admin-password
    push_secret automation n8n-secrets encryption-key /run/secrets/n8n-encryption-key
    push_secret automation hermes-automation-keys n8n-api-key /run/secrets/n8n-api-key

    echo "[k8s-secrets] Done"
  '';
in {
  systemd.services.k8s-secret-pusher = mkIf
    (config.services.k3s-cluster.enable && config.services.k3s-cluster.role == "server")
  {
    description = "Push sops-nix secrets to Kubernetes";
    after = ["k3s.service" "network-online.target"];
    wants = ["k3s.service" "network-online.target"];
    requires = ["k3s.service"];
    wantedBy = ["multi-user.target"];
    path = with pkgs; [kubectl coreutils gnugrep];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StandardOutput = "journal";
      StandardError = "journal";
      ExecStart = "${pwsh}";
    };
  };
}