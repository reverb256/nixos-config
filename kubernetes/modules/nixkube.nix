{...}: {
  config.kubernetes.objects = {
    none = {
      Namespace.ai-inference = {
        metadata.labels = {
          name = "ai-inference";
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
      };
      Namespace.nixkube = {
        metadata.labels = {
          name = "nixkube";
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
      };
    };
  };

  config.kubernetes.objects.nixkube = {
    # ── Default deny all ────────────────────────────────────────
    NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };
  };

}
