# ─────────────────────────────────────────────────────────────────
# K8s Secret Sync — populates K8s Secrets from sops-nix files
#
# Multiple Nix modules define empty K8s Secrets with comments like
# "Populated by kubectl-apply-k8s-secrets from sops-nix" — but
# that service was never implemented. This module fills that gap.
#
# It maps sops-nix secret paths (/run/secrets/...) to K8s Secret
# keys and runs a one-shot systemd service to populate them.
# ─────────────────────────────────────────────────────────────────

{ config, lib, pkgs, ... }:
let
  cfg = config.services.k8s-secret-sync;
  inherit (lib) mkEnableOption mkOption types mkIf;

  # ── sops → K8s Secret mapping ─────────────────────────────────
  # Each entry: { sopsPath; namespace; secretName; key; }
  # sopsPath is the /run/secrets/... path from sops-install-secrets
  secretMappings = [
    # ── Grafana ──────────────────────────────────────────────
    {
      sopsPath = "/run/secrets/grafana-oidc-client-secret";
      namespace = "monitoring";
      secretName = "grafana-oidc-secret";
      key = "client-secret";
    }
    {
      sopsPath = "/run/secrets/grafana-admin-password";
      namespace = "monitoring";
      secretName = "grafana-admin-secret";
      key = "admin-password";
    }
    # ── Automation (n8n) ─────────────────────────────────────
    {
      sopsPath = "/run/secrets/automation/n8n-admin-password";
      namespace = "automation";
      secretName = "n8n-secrets";
      key = "admin-password";
    }
    {
      sopsPath = "/run/secrets/automation/n8n-encryption-key";
      namespace = "automation";
      secretName = "n8n-secrets";
      key = "encryption-key";
    }
    {
      sopsPath = "/run/secrets/automation/n8n-api-key";
      namespace = "automation";
      secretName = "hermes-automation-keys";
      key = "n8n-api-key";
    }
    # ── Mission Control ──────────────────────────────────────
    {
      sopsPath = "/run/secrets/mission-control-auth-pass";
      namespace = "orchestration";
      secretName = "mission-control-secrets";
      key = "auth-pass";
    }
    {
      sopsPath = "/run/secrets/mission-control-api-key";
      namespace = "orchestration";
      secretName = "mission-control-secrets";
      key = "api-key";
    }
    # ── SearXNG ──────────────────────────────────────────────
    {
      sopsPath = "/run/secrets/searxng-secret-key";
      namespace = "search";
      secretName = "searxng-secrets";
      key = "secret-key";
    }
    # ── AI Inference Gateway ─────────────────────────────────
    {
      sopsPath = "/run/secrets/ai-gateway-zai-api-key";
      namespace = "ai-inference";
      secretName = "ai-inference-gateway-secrets";
      key = "api-keys";
    }
  ];
in {
  options.services.k8s-secret-sync = {
    enable = mkEnableOption "Sync sops-nix secrets to K8s Secrets";

    extraMappings = mkOption {
      type = types.listOf (types.submodule {
        options = {
          sopsPath = mkOption { type = types.str; };
          namespace = mkOption { type = types.str; };
          secretName = mkOption { type = types.str; };
          key = mkOption { type = types.str; };
        };
      });
      default = [];
      description = "Additional sops→K8s secret mappings";
    };

    requireAllSecrets = mkOption {
      type = types.bool;
      default = false;
      description = "Fail if any sops file is missing (safe for boot); false = skip missing";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.k8s-secret-sync = {
      description = "Sync sops-nix secrets to K8s Secrets";
      after = [ "k3s.service" "sops-install-secrets.service" "network.target" ];
      requires = [ "k3s.service" ];
      wants = [ "sops-install-secrets.service" ];
      wantedBy = [ "multi-user.target" ];
      before = [ "k8s-nix-deploy.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
        TimeoutStartSec = 120;
        Restart = "on-failure";
        RestartSec = 15;
      };

      path = with pkgs; [ kubectl coreutils gnused gnugrep ];

      script = let
        allMappings = secretMappings ++ cfg.extraMappings;
        # Group by (namespace, secretName) so we batch all keys for one secret
        grouped = builtins.groupBy (m: "${m.namespace}/${m.secretName}") allMappings;
      in ''
        set -euo pipefail
        echo "[k8s-secret-sync] Waiting for K8s API..."
        elapsed=0
        until kubectl get nodes &>/dev/null; do
          sleep 2
          elapsed=$((elapsed + 2))
          if [ $elapsed -ge 120 ]; then
            echo "[k8s-secret-sync] Timed out waiting for K8s API"
            exit 1
          fi
        done
        echo "[k8s-secret-sync] K8s API ready"

        # Build JSON patch for each secret (batch all keys per secret)
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (ns_secret: mappings: ''
          namespace="${lib.head (builtins.split "/" ns_secret)}"
          secretName="${lib.elemAt (lib.splitString "/" ns_secret) 1}"

          # Build patch data
          PATCH_DATA="{"
          FIRST=true
          ${lib.concatStringsSep "\n" (map (m: ''
            SOP_PATH="${m.sopsPath}"
            KEY="${m.key}"
            if [ -f "$SOP_PATH" ]; then
              VAL=$(cat "$SOP_PATH" | base64 -w0)
              if [ "$FIRST" = "true" ]; then FIRST=false; else PATCH_DATA="$PATCH_DATA,"; fi
              PATCH_DATA="$PATCH_DATA\"$KEY\":\"$VAL\""
            else
              ${lib.optionalString cfg.requireAllSecrets ''
                echo "[k8s-secret-sync] ERROR: $SOP_PATH not found (requireAllSecrets=true)"
                exit 1
              ''}
              echo "[k8s-secret-sync] WARN: $SOP_PATH not found, skipping $namespace/$secretName/$KEY"
            fi
          '') mappings)}
          PATCH_DATA="$PATCH_DATA}"

          if [ "$FIRST" = "false" ]; then
            echo "[k8s-secret-sync] Syncing $namespace/$secretName..."
            if kubectl get secret "$secretName" -n "$namespace" &>/dev/null; then
              # Secret exists — patch it
              kubectl patch secret "$secretName" -n "$namespace" -p "{\"data\":$PATCH_DATA}" 2>&1 | head -1
            else
              # Secret doesn't exist — create it
              kubectl create secret generic "$secretName" -n "$namespace" --from-literal=dummy=temp 2>&1 | head -1
              kubectl patch secret "$secretName" -n "$namespace" -p "{\"data\":$PATCH_DATA}" 2>&1 | head -1
            fi
          fi
        '') grouped)}

        echo "[k8s-secret-sync] Done."
      '';
    };
  };
}
