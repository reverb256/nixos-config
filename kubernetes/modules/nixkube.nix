# Nixkube — Nix store caching and CSI driver infrastructure
#
# Provides nix-store access to pods via nix-csi driver and a shared
# nix-cache StatefulSet. Runs on all nodes via DaemonSet.
#
# Resources: DaemonSet (nix-node), StatefulSet (nix-cache), Deployment (proxy),
# Services, ConfigMaps, Secrets, RBAC, PVC
#
# Uses importyaml for the live manifest (complex DaemonSet with 5 containers
# including CSI sidecars — not worth hand-converting).
{
  pkgs,
  lib,
  ...
}: {
  config.kubernetes.objects.none = {
    Namespace.ai-inference = {
      metadata.labels = {
        name = "ai-inference";
      };
    };
    Namespace.nixkube = {
      metadata.labels = {
        name = "nixkube";
      };
    };
  };

  # Import the full nixkube manifest from cleaned live YAML
  # This includes: DaemonSet, StatefulSet, Deployment, Services, ConfigMaps,
  # Secrets, ServiceAccounts, Role, RoleBinding, PVC
  config.importyaml.nixkube = {
    src = pkgs.runCommand "nixkube.yaml" { } ''
      cp ${../../kubernetes-manifests/nixkube/nixkube-clean.yaml} $out
    '';
  };
}
