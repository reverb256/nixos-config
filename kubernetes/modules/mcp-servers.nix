{pkgs, ...}: {
  # ── MCP Servers Namespace ───────────────────────────────────────
  config.kubernetes.objects = {
    none.Namespace.mcp = {
      metadata.labels = {
        name = "mcp";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    # ── Default deny all ──────────────────────────────────────────
    mcp.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };
  };
}
