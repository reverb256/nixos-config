{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf;
  secrets = {
    "ai-inference" = {
      "zai-api-key" = "ZAI_API_KEY";
      "huggingface-token" = "TOKEN";
      "nvidia-api-key" = "NVIDIA_API_KEY";
      "kilo-api-key" = "KILO_API_KEY";
      "opencode-api-key" = "OPENCODE_API_KEY";
    };
    "kelos-system" = {
      "opencode-credentials" = "OPENCODE_API_KEY";
    };
    "search" = {
      "searxng-secret" = "secret-key";
    };
    "orchestration" = {
      "mission-control-secrets" = "auth-pass";
    };
    "mining" = {
      "xmrig-proxy-secret" = "api-token";
    };
    "monitoring" = {
      "grafana-admin-secret" = "admin-password";
      "grafana-oidc-secret" = "client-secret";
      "openwebui-oidc-secret" = "client-secret";
      "vaultwarden-oidc-secret" = "client-secret";
    };
    "automation" = {
      "n8n-secrets" = "admin-password";
      "n8n-encryption-key" = "encryption-key";
      "hermes-automation-keys" = "n8n-api-key";
    };
  };
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
    };
    script = ''
      set -euo pipefail
      echo "[k8s-secrets] Waiting for K8s API..."
      for i in $(seq 1 60); do
        if kubectl get nodes >/dev/null 2>&1; then
          echo "[k8s-secrets] K8s API ready after $${i}s"
          break
        fi
        sleep 2
      done
      if ! kubectl get nodes >/dev/null 2>&1; then
        echo "[k8s-secrets] ERROR: K8s API not available after 120s"
        exit 1
      fi
      echo "[k8s-secrets] Applying sops-nix secrets to Kubernetes..."
    '' + lib.concatStringsSep "\n" (lib.flatten (lib.mapAttrsToList (ns: secrets:
      lib.mapAttrsToList (name: key: ''
        FILE="/run/secrets/${name}"
        if [ ! -f "$FILE" ]; then
          echo "[k8s-secrets] SKIP ${ns}/${name} - file not ready"
        else
          VALUE=$(cat "$FILE")
          if kubectl get secret "${name}" -n "${ns}" >/dev/null 2>&1; then
            kubectl patch secret "${name}" -n "${ns}" -p "{\"stringData\":{\"${key}\":\"$VALUE\"}}" 2>/dev/null && \
              echo "[k8s-secrets] OK ${ns}/${name} (${key})" || \
              echo "[k8s-secrets] FAIL update ${ns}/${name}"
          else
            kubectl create secret generic "${name}" -n "${ns}" --from-literal="${key}=$VALUE" --dry-run=client -o yaml | kubectl apply -f - && \
              echo "[k8s-secrets] OK ${ns}/${name} (created)" || \
              echo "[k8s-secrets] FAIL create ${ns}/${name}"
          fi
        fi
      '') secrets)) secrets) + ''
      echo "[k8s-secrets] Done"
    '';
  };
}
