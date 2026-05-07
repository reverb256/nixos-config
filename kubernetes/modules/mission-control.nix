{pkgs, ...}: {
  # ── Orchestration (Mission Control) Namespace ───────────────────
  config.kubernetes.objects = {
    none.Namespace.orchestration = {
      metadata.labels = {
        name = "orchestration";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    # ── Default deny all ──────────────────────────────────────────
    orchestration.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };
  };
}
