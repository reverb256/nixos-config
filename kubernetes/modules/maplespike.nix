{ ... }: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects = {
    # ── Namespaces ──────────────────────────────────────────
    none.Namespace.maplespike = {
      metadata.labels = managed // {
        name = "maplespike";
      };
    };
    none.Namespace.maplespike-dev = {
      metadata.labels = managed // {
        name = "maplespike-dev";
      };
    };
  };
}
