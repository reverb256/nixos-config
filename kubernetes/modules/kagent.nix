{pkgs, ...}: {
  # ── KAgent Namespace ────────────────────────────────────────────
  config.kubernetes.objects = {
    none.Namespace.kagent = {
      metadata.labels = {
        name = "kagent";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    # ── Default deny all ──────────────────────────────────────────
    kagent.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };
  };
}
