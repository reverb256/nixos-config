{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.gitea-cert-sync;

  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.gitea-cert-sync = {
    enable = mkEnableOption "Sync cluster-ca TLS certs to Gitea K8s secret";

    certPath = mkOption {
      type = types.str;
      default = "/etc/ssl/cluster-ca/leaf.crt";
      description = "Path to TLS leaf certificate";
    };

    keyPath = mkOption {
      type = types.str;
      default = "/etc/ssl/cluster-ca/leaf.key";
      description = "Path to TLS leaf private key";
    };

    secretName = mkOption {
      type = types.str;
      default = "gitea-tls";
      description = "Name of the K8s TLS secret";
    };

    namespace = mkOption {
      type = types.str;
      default = "gitea";
      description = "K8s namespace for the secret";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.gitea-cert-sync = {
      description = "Sync cluster-ca TLS certs to Gitea K8s secret";
      after = ["k3s.service" "cluster-ca-init.service"];
      requires = ["k3s.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
        RemainAfterExit = true;
      };
      path = [pkgs.kubectl pkgs.openssl pkgs.coreutils];
      script = ''
        set -euo pipefail

        echo "[gitea-cert-sync] Waiting for K8s API..."
        elapsed=0
        until kubectl get nodes &>/dev/null; do
          sleep 5
          elapsed=$((elapsed + 5))
          if [ $elapsed -ge 120 ]; then
            echo "[gitea-cert-sync] Timed out waiting for K8s API"
            exit 1
          fi
        done

        # Wait for cluster-ca certs to exist
        if [ ! -f "${cfg.certPath}" ] || [ ! -f "${cfg.keyPath}" ]; then
          echo "[gitea-cert-sync] TLS certs not yet available at ${cfg.certPath}"
          exit 0
        fi

        # Compute hash of current cert to detect changes
        CURRENT_HASH=$(sha256sum "${cfg.certPath}" | awk '{print $1}')

        # Check if secret exists and has matching hash
        EXISTING_HASH=$(kubectl get secret ${cfg.secretName} -n ${cfg.namespace} \
          -o jsonpath='{.metadata.annotations.cert-hash}' 2>/dev/null || echo "")

        if [ "$CURRENT_HASH" = "$EXISTING_HASH" ]; then
          echo "[gitea-cert-sync] Cert hash unchanged — skipping sync"
          exit 0
        fi

        echo "[gitea-cert-sync] Syncing TLS cert (hash: $CURRENT_HASH)..."

        # Create or update the TLS secret
        kubectl create secret tls ${cfg.secretName} \
          --cert="${cfg.certPath}" \
          --key="${cfg.keyPath}" \
          -n ${cfg.namespace} \
          --dry-run=client -o yaml | kubectl apply -f -

        # Annotate with cert hash for future change detection
        kubectl annotate secret ${cfg.secretName} -n ${cfg.namespace} \
          --overwrite cert-hash="$CURRENT_HASH"

        echo "[gitea-cert-sync] Secret ${cfg.secretName} updated"

        # Restart Gitea deployment to pick up new cert
        kubectl rollout restart deployment/gitea -n ${cfg.namespace} 2>/dev/null || true
        echo "[gitea-cert-sync] Gitea deployment restart triggered"
      '';
    };

    # Timer for periodic cert sync (every 6 hours)
    systemd.timers.gitea-cert-sync = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "6h";
        Persistent = true;
      };
    };
  };
}
