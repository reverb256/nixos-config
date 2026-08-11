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
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.k8s-secret-sync;
  inherit (lib) mkEnableOption mkOption types mkIf;

  # ── sops → K8s Secret mapping ─────────────────────────────────
  # Each entry: { sopsPath; namespace; secretName; key; }
  # sopsPath is the /run/secrets/... path from sops-install-secrets
  secretMappings = [
    # ── MapleSpike (D3) ─────────────────────────────────────────
    # NOTE: telegram-secrets:bot-token is currently empty (0 bytes).
    # The sops secret /run/secrets/telegram-bot-token uses format=yaml
    # and the actual token value is nested under a `data` key.
    # Fix: change the secret format to "binary" in sops-secrets-registry.nix
    # or use `sops -d --output-type raw` to get the bare token.
    # Currently maps from /run/secrets/telegram-bot-token (needs decryption fix).
    {
      sopsPath = "/run/secrets/telegram-bot-token";
      namespace = "maplespike";
      secretName = "telegram-secrets";
      key = "bot-token";
    }
    {
      sopsPath = "/run/secrets/cachix-token";
      namespace = "maplespike";
      secretName = "cachix-secrets";
      key = "cachix-token";
    }
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
    # ── AI inference ─────────────────────────────────────────
    {
      sopsPath = "/run/secrets/huggingface-token";
      namespace = "ai-inference";
      secretName = "hf-token";
      key = "token";
    }
    {
      sopsPath = "/run/secrets/nvidia-api-key";
      namespace = "ai-inference";
      secretName = "nvidia-api-key";
      key = "NVIDIA_API_KEY";
    }
    {
      sopsPath = "/run/secrets/kilo-api-key";
      namespace = "ai-inference";
      secretName = "kilo-api-key";
      key = "KILO_API_KEY";
    }
    {
      sopsPath = "/run/secrets/opencode-api-key";
      namespace = "ai-inference";
      secretName = "opencode-api-key";
      key = "OPENCODE_API_KEY";
    }
    {
      sopsPath = "/run/secrets/opencode-go-api-key";
      namespace = "ai-inference";
      secretName = "opencode-go-api-key";
      key = "OPENCODE_GO_API_KEY";
    }
    {
      sopsPath = "/run/secrets/frostbite-postgres";
      namespace = "ai-inference";
      secretName = "frostbite-secrets";
      key = "postgres-password";
    }
    # ── Mission Control ──────────────────────────────────────
    # ── OAuth2 proxy ─────────────────────────────────────────
    {
      sopsPath = "/run/secrets/central-auth-client-secret";
      namespace = "auth";
      secretName = "oauth2-proxy-secrets";
      key = "client-secret";
    }
    {
      sopsPath = "/run/secrets/central-auth-cookie-secret";
      namespace = "auth";
      secretName = "oauth2-proxy-secrets";
      key = "cookie-secret";
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
  ];
in {
  options.services.k8s-secret-sync = {
    enable = mkEnableOption "Sync sops-nix secrets to K8s Secrets";

    extraMappings = mkOption {
      type = types.listOf (types.submodule {
        options = {
          sopsPath = mkOption {type = types.str;};
          namespace = mkOption {type = types.str;};
          secretName = mkOption {type = types.str;};
          key = mkOption {type = types.str;};
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
      # Namespace resources are owned by the declarative manifest layer. Wait
      # for that layer to finish before attempting to create namespaced Secrets.
      after = [
        "k3s.service"
        "sops-install-secrets.service"
        "k8s-nix-deploy.service"
        "network.target"
      ];
      requires = ["k3s.service" "k8s-nix-deploy.service"];
      wants = ["sops-install-secrets.service"];
      wantedBy = ["multi-user.target"];
      # k8s-nix-deploy is the prerequisite; do not add a reverse ordering edge
      # here or systemd would create a dependency cycle.
      before = [];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
        TimeoutStartSec = 120;
        Restart = "on-failure";
        RestartSec = 15;
      };

      path = with pkgs; [kubectl coreutils gnused gnugrep];

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

        # Namespaces are declarative resources, not runtime side effects of
        # secret synchronization. Fail with an explicit dependency error if
        # the manifest layer did not create every target namespace.
        for namespace in ${lib.concatStringsSep " " (lib.unique (map (m: m.namespace) (secretMappings ++ cfg.extraMappings)))}; do
          if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
            echo "[k8s-secret-sync] ERROR: required namespace $namespace is absent after k8s-nix-deploy" >&2
            exit 1
          fi
        done

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
              '')
              mappings)}
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
          '')
          grouped)}

        echo "[k8s-secret-sync] Done."
      '';
    };
    # ── Reconciliation timer (hourly, random offset) ──────────
    systemd.timers.k8s-secret-sync = {
      description = "Periodic K8s secret reconciliation (sops-nix → K8s)";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "600"; # 0-10 min random delay to avoid thundering herd
        Persistent = true;
      };
    };
  };
}
