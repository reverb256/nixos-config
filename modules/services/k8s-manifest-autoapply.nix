{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.k8s-manifest-autoapply;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;

  manifestDir = "/etc/nixos/kubernetes-manifests";

  manifestDirs = [
    "common"
    "rbac"
    "networking"
    "storage"
    "gpu"
    "security"
    "security-baseline"
    "network-policies"
    "scheduling"
    "resource-allocation"
    "pod-disruption-budgets"
    "system"
    "mining"
    "ai-inference"
    "search"
    "ingress"
    "monitoring"
    "health-checks"
  ];

  applyScript = pkgs.writeShellScript "k8s-apply-manifests" ''
    set -euo pipefail

    echo "[k8s-manifests] Waiting for K3s API to be ready..."
    WAIT_TIMEOUT=60
    elapsed=0
    until ${pkgs.kubectl}/bin/kubectl get nodes &>/dev/null; do
      sleep 5
      elapsed=$((elapsed + 5))
      if [ $elapsed -ge $WAIT_TIMEOUT ]; then
        echo "[k8s-manifests] Timed out waiting for API after $WAIT_TIMEOUT seconds"
        exit 0
      fi
    done
    echo "[k8s-manifests] API ready."

    for dir in ${lib.concatStringsSep " " manifestDirs}; do
      dir_path="${manifestDir}/$dir"
      if [ -d "$dir_path" ]; then
        for f in "$dir_path"/*.yaml; do
          basename=$(basename "$f")
          case "$basename" in
            test-*|debug-*|old-*|*-debug-*|*-test-*|*-old-*|*-draft-*|*-yunikorn*|*-direct*|*-new*|*-simple*|*-per-gpu*|*README*|*.md|*.nix|*.txt|*-forge.yaml|*-forge-*)
              continue
              ;;
          esac
          echo "[k8s-manifests] Applying $dir/$basename"
          ${pkgs.kubectl}/bin/kubectl apply -f "$f" 2>&1 || true
        done
      fi
    done

    echo "[k8s-manifests] All manifests applied."
  '';
in
{
  options.services.k8s-manifest-autoapply = {
    enable = mkEnableOption "Auto-apply Kubernetes manifests on boot";
  };

  config = mkIf cfg.enable {
    systemd.services.k8s-manifest-autoapply = {
      description = "Auto-apply Kubernetes manifests on boot";
      after = [ "k3s.service" ];
      requires = [ "k3s.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
        ExecStart = toString applyScript;
        RemainAfterExit = true;
      };
    };
  };
}
