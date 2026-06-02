# MapleSpike GHCR Image Pull Secret Configuration
# Manages GHCR authentication for pulling container images
# Uses GitHub PAT from agenix for automatic secret rotation
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.maplespike-ghcr-secret;
in {
  options.services.maplespike-ghcr-secret = {
    enable = lib.mkEnableOption "MapleSpike GHCR image pull secret management";

    githubTokenPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/agenix/github-token";
      description = "Path to GitHub PAT in agenix";
    };

    secretName = lib.mkOption {
      type = lib.types.str;
      default = "ghcr-pull";
      description = "Name of the Kubernetes secret";
    };

    namespaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["maplespike-prod" "maplespike-dev"];
      description = "Namespaces where the secret should be created";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create systemd service to bootstrap GHCR pull secrets
    systemd.services.maplespike-ghcr-secret = {
      description = "Bootstrap MapleSpike GHCR image pull secrets";
      after = ["k3s.service"];
      requires = ["k3s.service"];
      before = ["k8s-nix-deploy.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
        RemainAfterExit = true;
      };
      path = [pkgs.kubectl pkgs.coreutils pkgs.jq];
      script = ''
        set -euo pipefail

        echo "[maplespike-ghcr-secret] Waiting for K8s API..."
        elapsed=0
        until kubectl get nodes &>/dev/null; do
          sleep 5
          elapsed=$((elapsed + 5))
          if [ $elapsed -ge 120 ]; then
            echo "[maplespike-ghcr-secret] Timed out waiting for K8s API"
            exit 1
          fi
        done

        # Read GitHub token from agenix
        GITHUB_TOKEN=$(cat ${cfg.githubTokenPath} 2>/dev/null || echo "")

        if [ -z "$GITHUB_TOKEN" ]; then
          echo "[maplespike-ghcr-secret] ERROR: Could not read GitHub token from ${cfg.githubTokenPath}"
          exit 1
        fi

        # Create/update secrets in each namespace
        ${lib.concatMapStrings (ns: ''
            echo "[maplespike-ghcr-secret] Processing namespace: ${ns}"

            if kubectl get secret ${cfg.secretName} -n ${ns} &>/dev/null; then
              echo "[maplespike-ghcr-secret] Secret ${cfg.secretName} exists in ${ns}, updating..."
              kubectl delete secret ${cfg.secretName} -n ${ns}
            fi

            kubectl create secret docker-registry ${cfg.secretName} \
              -n ${ns} \
              --docker-server=ghcr.io \
              --docker-username=reverb256 \
              --docker-password="$GITHUB_TOKEN" \
              --docker-email=j_kroeker@reverb256.ca

            echo "[maplespike-ghcr-secret] Created/updated secret in ${ns}"
          '')
          cfg.namespaces}

        echo "[maplespike-ghcr-secret] Done."
      '';
    };

    # Daily sync to keep secrets updated
    systemd.timers.maplespike-ghcr-secret-sync = {
      description = "Sync MapleSpike GHCR secrets daily";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    systemd.services.maplespike-ghcr-secret-sync = {
      description = "Sync MapleSpike GHCR image pull secrets";
      after = ["k3s.service" "maplespike-ghcr-secret.service"];
      requires = ["k3s.service"];
      serviceConfig = {
        Type = "oneshot";
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
      };
      path = [pkgs.kubectl pkgs.coreutils];
      script = ''
        set -euo pipefail

        GITHUB_TOKEN=$(cat ${cfg.githubTokenPath} 2>/dev/null || echo "")
        if [ -z "$GITHUB_TOKEN" ]; then
          echo "[maplespike-ghcr-secret-sync] Could not read token, skipping"
          exit 0
        fi

        ${lib.concatMapStrings (ns: ''
            kubectl delete secret ${cfg.secretName} -n ${ns} --ignore-not-found
            kubectl create secret docker-registry ${cfg.secretName} \
              -n ${ns} \
              --docker-server=ghcr.io \
              --docker-username=reverb256 \
              --docker-password="$GITHUB_TOKEN" \
              --docker-email=j_kroeker@reverb256.ca || true
          '')
          cfg.namespaces}

        echo "[maplespike-ghcr-secret-sync] Synced secrets"
      '';
    };
  };
}
