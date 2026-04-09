# Cluster infrastructure — security baseline, storage, common resources
#
# Security policies, global network defaults, and the nix-csi driver.
# The CSI driver YAML is imported directly (complex DaemonSet with sidecars).
{
  pkgs,
  config,
  lib,
  ...
}:
let
  pssLabels = {
    "pod-security.kubernetes.io/enforce" = "baseline";
    "pod-security.kubernetes.io/audit" = "restricted";
    "pod-security.kubernetes.io/warn" = "restricted";
  };
in
{
  # ── Cluster-scoped PriorityClasses ───────────────────────────
  config.kubernetes.objects.none = {
    PriorityClass.high-priority-ai = {
      value = 1000;
      globalDefault = false;
      description = "High priority for AI inference workloads. Preempts mining pods.";
    };
    PriorityClass.low-priority-mining = {
      value = 100;
      globalDefault = false;
      description = "Low priority for cryptocurrency mining. Preempted by AI workloads.";
    };
  };

  # ── Namespace PSS labels (search + default) ─────────────────
  # SearXNG namespace is already defined in searxng.nix, but the
  # security-baseline applies PSS labels to additional namespaces.
  config.kubernetes.objects.default = {
    Namespace.default = {
      metadata.labels = pssLabels // {
        name = "default";
      };
    };
    # Default deny all traffic
    NetworkPolicy.default-deny-all = {
      metadata.labels.policy = "default-deny";
      spec = {
        podSelector = { };
        policyTypes = [
          "Ingress"
          "Egress"
        ];
      };
    };
    # Allow DNS
    NetworkPolicy.allow-dns = {
      metadata.labels.policy = "allow-dns";
      spec = {
        podSelector = { };
        policyTypes = [ "Egress" ];
        egress = [
          {
            to = [ { namespaceSelector.matchLabels.name = "kube-system"; } ];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
              {
                protocol = "TCP";
                port = 53;
              }
            ];
          }
        ];
      };
    };
    # Security context defaults ConfigMap
    ConfigMap.security-context-defaults = {
      data = {
        runAsUser = "1001";
        runAsGroup = "1001";
        fsGroup = "1001";
        runAsNonRoot = "true";
        allowPrivilegeEscalation = "false";
        readOnlyRootFilesystem = "true";
        seccompProfileType = "RuntimeDefault";
      };
    };
  };

  # ── Import nix-csi driver YAML directly ─────────────────────
  # The CSI DaemonSet is complex (3 containers, init containers, RBAC)
  # and already tested — import rather than hand-convert.
  config.importyaml.nix-csi-driver = {
    src = pkgs.runCommand "nix-csi-driver.yaml" { } ''
      # Remove volumeLifecycleModes — field is immutable on existing CSIDriver
      ${pkgs.yq-go}/bin/yq 'del(.spec.volumeLifecycleModes)' \
        ${../../kubernetes-manifests/storage/nix-csi-driver.yaml} > $out
    '';
  };
}
