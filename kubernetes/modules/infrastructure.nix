{
  pkgs,
  config,
  lib,
  ...
}: let
  pssLabels = {
    "pod-security.kubernetes.io/enforce" = "baseline";
    "pod-security.kubernetes.io/audit" = "restricted";
    "pod-security.kubernetes.io/warn" = "restricted";
  };
in {
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

  config.kubernetes.objects.default = {
    Namespace.default = {
      metadata.labels =
        pssLabels
        // {
          name = "default";
        };
    };
    NetworkPolicy.default-deny-all = {
      metadata.labels.policy = "default-deny";
      spec = {
        podSelector = {};
        policyTypes = [
          "Ingress"
          "Egress"
        ];
      };
    };
    NetworkPolicy.allow-dns = {
      metadata.labels.policy = "allow-dns";
      spec = {
        podSelector = {};
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{namespaceSelector.matchLabels.name = "kube-system";}];
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
}
