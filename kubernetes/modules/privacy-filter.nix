{pkgs, ...}: {
  # ── Privacy Filter Namespace ────────────────────────────────────
  config.kubernetes.objects = {
    none.Namespace.privacy-filter = {
      metadata.labels = {
        name = "privacy-filter";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    # ── Default deny all ──────────────────────────────────────────
    privacy-filter.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };
  };
}
