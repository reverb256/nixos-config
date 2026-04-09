# Deploys Kubernetes manifests from Nix-generated store path on boot.
#
# Replaces k8s-manifest-autoapply.nix — instead of applying 17 directories
# of raw YAML files from /etc/nixos/kubernetes-manifests/, this applies
# the single Nix-generated manifest file produced by `nix build .#k8s-manifests`.
#
# The manifest path is passed via `manifestPackage` option (defaults to
# the flake's k8s-manifests output).
#
# Runs on control-plane node only (zephyr) since K8s API is global.
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
              exit 0
            fi
          done
          echo "[k8s-nix-deploy] K3s API ready."

          echo "[k8s-nix-deploy] Applying manifests from: $MANIFEST"
          ${pkgs.kubectl}/bin/kubectl apply -f "$MANIFEST" 2>&1 || true

          echo "[k8s-nix-deploy] Done."
        '';
        RemainAfterExit = true;
      };
    };
  };
}
