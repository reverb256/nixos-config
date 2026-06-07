{
  config,
  lib,
  pkgs,
  k8sManifestPackage ? null,
  ...
}: let
  cfg = config.services.k8s-nix-deploy;
  k3sCfg = config.services.k3s-cluster or {};
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in {
  options.services.k8s-nix-deploy = {
    enable = mkEnableOption "Deploy K8s manifests from Nix store on boot";
    manifestPackage = mkOption {
      type = types.package;
      description = "Package containing the generated K8s manifest YAML file";
      default = k8sManifestPackage;
    };
    apiServerAddress = mkOption {
      type = types.str;
      default = k3sCfg.serverAddr or "https://127.0.0.1:6443";
      description = "Kubernetes API server address for kubectl";
    };
    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = k3sCfg.tokenFile or null;
      description = "File containing the cluster auth token (null = use local kubeconfig)";
    };
    prune = mkOption {
      type = types.bool;
      default = false;
      description = "Remove resources not in the manifest (use with caution on first migration)";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.k8s-nix-deploy = {
      description = "Deploy Kubernetes manifests from Nix store";
      after = ["k3s.service"];
      requires = ["k3s.service"];
      wantedBy = [];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "k8s-nix-deploy" ''
          set -euo pipefail

          MANIFEST="${cfg.manifestPackage}"

          # Build kubectl command — use server+token auth if configured, else fall back to kubeconfig
          KUBECTL="${pkgs.kubectl}/bin/kubectl"
          ${lib.optionalString (cfg.tokenFile != null) ''
            TOKEN=$(cat ${cfg.tokenFile})
            KUBECTL="$KUBECTL --server=${cfg.apiServerAddress} --token=$TOKEN --insecure-skip-tls-verify"
          ''}
          ${lib.optionalString (cfg.tokenFile == null) ''
            export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
          ''}

          echo "[k8s-nix-deploy] Waiting for K3s API..."
          elapsed=0
          until $KUBECTL get nodes &>/dev/null; do
            sleep 5
            elapsed=$((elapsed + 5))
            if [ $elapsed -ge 120 ]; then
              echo "[k8s-nix-deploy] Timed out waiting for K3s API"
              exit 1
            fi
          done
          echo "[k8s-nix-deploy] K3s API ready."

          echo "[k8s-nix-deploy] Applying manifests from: $MANIFEST"
          ${
            if cfg.prune
            then ''
              $KUBECTL apply --prune -l managed-by=easykubenix -f "$MANIFEST" 2>&1
            ''
            else ''
              $KUBECTL apply -f "$MANIFEST" 2>&1
            ''
          }

          echo "[k8s-nix-deploy] Done."
        '';
        RemainAfterExit = true;
      };
    };
  };
}
