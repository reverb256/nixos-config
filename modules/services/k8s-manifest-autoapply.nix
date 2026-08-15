# Auto-deploys Kubernetes manifests from /etc/nixos/kubernetes-manifests/ on boot
# Runs after K3s is ready, applies all manifests, then exits.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.k8s-manifest-autoapply;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;

  manifestDir = "/etc/nixos/kubernetes-manifests";

  # Active manifest directories to apply (in order)
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
    "calico" # Calico CNI (VXLAN, policy-enforcing)
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

    # Apply each directory in order
    for dir in ${lib.concatStringsSep " " manifestDirs}; do
      dir_path="${manifestDir}/$dir"
      if [ -d "$dir_path" ]; then
        # ── calico two-phase apply (2026-08-15 durable fix) ──────────────────
        # The alphabetical glob applied tigera-operator.yaml AFTER the CR
        # manifests, so Installation/IPPool/APIServer failed ("no matches for
        # kind") and the operator provisioned nothing -> every pod sandbox
        # died "plugin type=calico failed". The operator manifest creates the
        # CRDs, so apply it FIRST, wait for the CRD group, then apply the rest
        # with retry (the operator needs a moment to become ready).
        if [ "$dir" = "calico" ]; then
          echo "[k8s-manifests] calico phase 1: tigera-operator (CRD source)"
          ${pkgs.kubectl}/bin/kubectl apply -f "$dir_path/tigera-operator.yaml" 2>&1 || true
          # Wait until the Calico CRDs are established (up to 60s)
          CRD_WAIT=60; crd_elapsed=0
          until ${pkgs.kubectl}/bin/kubectl get crd installations.operator.tigera.io &>/dev/null; do
            sleep 3
            crd_elapsed=$((crd_elapsed + 3))
            if [ $crd_elapsed -ge $CRD_WAIT ]; then
              echo "[k8s-manifests] WARNING: calico CRDs not ready after ''${CRD_WAIT}s"
              break
            fi
          done
          echo "[k8s-manifests] calico phase 2: CR manifests (with retry)"
        fi
        # Apply only .yaml files that don't start with test/old/draft prefixes
        for f in "$dir_path"/*.yaml; do
          basename=$(basename "$f")
          # Skip test, debug, old, and alternative manifests
          case "$basename" in
            test-*|debug-*|old-*|*-debug-*|*-test-*|*-old-*|*-draft-*|*-yunikorn*|*-direct*|*-new*|*-simple*|*-per-gpu*|*README*|*.md|*.nix|*.txt|*-forge.yaml|*-forge-*)
              continue
              ;;
          esac
          # Skip the operator manifest in the general pass (already applied).
          [ "$dir" = "calico" ] && [ "$basename" = "tigera-operator.yaml" ] && continue
          echo "[k8s-manifests] Applying $dir/$basename"
          ${pkgs.kubectl}/bin/kubectl apply -f "$f" 2>&1 || true
          # In calico phase 2, retry CR manifests that raced the operator.
          if [ "$dir" = "calico" ] && echo "$basename" | grep -qE "^(tigera-installation|tigera-ippool|tigera-apiserver|felix-configuration|bgp-config|calico-node-clusterrole|network-policies)"; then
            retry=0
            until ${pkgs.kubectl}/bin/kubectl apply -f "$f" >/dev/null 2>&1; do
              retry=$((retry + 1))
              [ $retry -ge 10 ] && { echo "[k8s-manifests] give up on $basename"; break; }
              sleep 5
            done
            echo "[k8s-manifests] calico CR applied: $basename (retries=$retry)"
          fi
        done
      fi
    done

    echo "[k8s-manifests] All manifests applied."
  '';
in {
  options.services.k8s-manifest-autoapply = {
    enable = mkEnableOption "Auto-apply Kubernetes manifests on boot";
  };

  config = mkIf cfg.enable {
    systemd.services.k8s-manifest-autoapply = {
      description = "Auto-apply Kubernetes manifests on boot";
      after = ["k3s.service"];
      requires = ["k3s.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
        ExecStart = toString applyScript;
        RemainAfterExit = true;
        # No restart — oneshot runs once on boot. If K3s isn't ready,
        # systemd will try again on next boot.
        # Restart=on-failure causes deadlock with switch-to-configuration.
      };
    };
  };
}
