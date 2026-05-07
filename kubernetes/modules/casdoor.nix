{pkgs, ...}: {
  # ── Auth (Casdoor) Namespace ────────────────────────────────────
  config.kubernetes.objects = {
    none.Namespace.auth = {
      metadata.labels = {
        name = "auth";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    # ── Default deny all ──────────────────────────────────────────
    auth.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };
  };
}
