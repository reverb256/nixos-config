# vLLM TurboQuant GHCR — Push + Pull Secret Management
#
# Builds the vLLM TurboQuant declarative fixes:
# 1. Pushes the image to GHCR using GitHub PAT from sops-nix
# 2. Creates/refreshes GHCR pull secret in ai-inference namespace
# 3. Updates the easykubenix deployment to reference GHCR image
#
# Depends on: podman, sops-nix (github-token)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.vllm-turboquant-ghcr;
in {
  options.services.vllm-turboquant-ghcr = {
    enable = lib.mkEnableOption "vLLM TurboQuant GHCR push + pull secret";

    imageTag = lib.mkOption {
      type = lib.types.str;
      default = "0.21.1";
      description = "Image tag for GHCR";
    };

    ghcrRepo = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/reverb256/vllm-turboquant";
      description = "GHCR repository path";
    };

    ghcrUser = lib.mkOption {
      type = lib.types.str;
      default = "reverb256";
      description = "GHCR username";
    };

    ghcrEmail = lib.mkOption {
      type = lib.types.str;
      default = "j_kroeker@reverb256.ca";
      description = "GHCR email for pull secret";
    };

    githubTokenPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/github-token";
      description = "Path to GitHub PAT in sops-nix";
    };

    # comma-separated list of ns where the pull secret gets created
    namespaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["ai-inference" "maplespike-prod"];
      description = "Namespaces for GHCR pull secret";
    };

    pullSecretName = lib.mkOption {
      type = lib.types.str;
      default = "ghcr-pull";
      description = "Name of the K8s pull secret";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── GHCR Image Push Service (one-shot) ──────────────────────
    # Pushes the locally-built vllm-turboquant image to GHCR
    # Run manually: systemctl start vllm-ghcr-push
    systemd.services.vllm-ghcr-push = {
      description = "Push vLLM TurboQuant image to GHCR";
      after = ["network-online.target"];
      requires = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = "XDG_RUNTIME_DIR=/run/user/1000";
      };
      path = [pkgs.podman];
      script = ''
        set -euo pipefail

        GITHUB_TOKEN=$(cat ${cfg.githubTokenPath} 2>/dev/null || echo "")
        if [ -z "$GITHUB_TOKEN" ]; then
          echo "[vllm-ghcr-push] ERROR: No GitHub token at ${cfg.githubTokenPath}"
          exit 1
        fi

        echo "[vllm-ghcr-push] Authenticating with GHCR..."
        echo "$GITHUB_TOKEN" | podman login ghcr.io -u ${cfg.ghcrUser} --password-stdin

        echo "[vllm-ghcr-push] Tagging local image..."
        podman tag localhost/vllm-turboquant:${cfg.imageTag} ${cfg.ghcrRepo}:${cfg.imageTag}
        podman tag localhost/vllm-turboquant:${cfg.imageTag} ${cfg.ghcrRepo}:latest

        echo "[vllm-ghcr-push] Pushing to GHCR..."
        podman push ${cfg.ghcrRepo}:${cfg.imageTag}
        podman push ${cfg.ghcrRepo}:latest

        echo "[vllm-ghcr-push] Done."
      '';
    };

    # ── GHCR Pull Secret Bootstrap (same pattern as maplespike-ghcr-secret) ──
    systemd.services.vllm-ghcr-secret = {
      description = "Bootstrap vLLM GHCR image pull secret in K8s";
      after = ["k3s.service"];
      requires = ["k3s.service"];
      before = ["k8s-nix-deploy.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 10;
      };
      path = [pkgs.kubectl pkgs.coreutils];
      script = ''
        set -euo pipefail

        echo "[vllm-ghcr-secret] Waiting for K8s API..."
        elapsed=0
        until kubectl get nodes &>/dev/null; do
          sleep 5
          elapsed=$((elapsed + 5))
          if [ $elapsed -ge 120 ]; then
            echo "[vllm-ghcr-secret] Timed out waiting for K8s API"
            exit 1
          fi
        done

        GITHUB_TOKEN=$(cat ${cfg.githubTokenPath} 2>/dev/null || echo "")
        if [ -z "$GITHUB_TOKEN" ]; then
          echo "[vllm-ghcr-secret] ERROR: No token at ${cfg.githubTokenPath}"
          exit 1
        fi

        ${lib.concatMapStrings (ns: ''
            echo "[vllm-ghcr-secret] Creating pull secret in ${ns}..."
            kubectl delete secret ${cfg.pullSecretName} -n ${ns} --ignore-not-found

            kubectl create secret docker-registry ${cfg.pullSecretName} \
              -n ${ns} \
              --docker-server=ghcr.io \
              --docker-username=${cfg.ghcrUser} \
              --docker-password="$GITHUB_TOKEN" \
              --docker-email=${cfg.ghcrEmail}

            # Annotate to prevent easykubenix from deleting
            kubectl annotate secret ${cfg.pullSecretName} -n ${ns} \
              "managed-by=vllm-ghcr-secret" --overwrite
          '')
          cfg.namespaces}

        echo "[vllm-ghcr-secret] Done."
      '';
    };

    # Daily sync to keep secrets fresh
    systemd.timers.vllm-ghcr-secret-sync = {
      description = "Daily vLLM GHCR secret sync";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    systemd.services.vllm-ghcr-secret-sync = {
      description = "Sync vLLM GHCR pull secrets";
      after = ["k3s.service"];
      requires = ["k3s.service"];
      path = [pkgs.kubectl pkgs.coreutils];
      script = ''
        set -euo pipefail

        GITHUB_TOKEN=$(cat ${cfg.githubTokenPath} 2>/dev/null || echo "")
        if [ -z "$GITHUB_TOKEN" ]; then
          echo "[vllm-ghcr-secret-sync] No token, skipping"
          exit 0
        fi

        ${lib.concatMapStrings (ns: ''
            kubectl delete secret ${cfg.pullSecretName} -n ${ns} --ignore-not-found
            kubectl create secret docker-registry ${cfg.pullSecretName} \
              -n ${ns} \
              --docker-server=ghcr.io \
              --docker-username=${cfg.ghcrUser} \
              --docker-password="$GITHUB_TOKEN" \
              --docker-email=${cfg.ghcrEmail} || true
            kubectl annotate secret ${cfg.pullSecretName} -n ${ns} \
              "managed-by=vllm-ghcr-secret" --overwrite || true
          '')
          cfg.namespaces}

        echo "[vllm-ghcr-secret-sync] Synced."
      '';
    };
  };
}
