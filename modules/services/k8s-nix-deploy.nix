{
  config,
  lib,
  pkgs,
  k8sManifestPackage ? null,
  ...
}:
let
  cfg = config.services.k8s-nix-deploy;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkDefault
    ;
in
{
  options.services.k8s-nix-deploy = {
    enable = mkEnableOption "Deploy K8s manifests from Nix store on boot";
    manifestPackage = mkOption {
      type = types.package;
      description = "Package containing the generated K8s manifest YAML file";
      default = k8sManifestPackage;
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
      after = [ "k3s.service" ];
      requires = [ "k3s.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
        ExecStart = pkgs.writeShellScript "k8s-nix-deploy" ''
          set -euo pipefail

          MANIFEST="${cfg.manifestPackage}"

          echo "[k8s-nix-deploy] Waiting for K3s API..."
          elapsed=0
          until ${pkgs.kubectl}/bin/kubectl get nodes &>/dev/null; do
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
              ${pkgs.kubectl}/bin/kubectl apply --prune -l managed-by=easykubenix -f "$MANIFEST" 2>&1
            ''
            else ''
              ${pkgs.kubectl}/bin/kubectl apply -f "$MANIFEST" 2>&1
            ''
          }

          echo "[k8s-nix-deploy] Done."
        '';
        RemainAfterExit = true;
      };
    };
  };
}
