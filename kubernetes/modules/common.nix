{...}: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  # Exclude generated manifests from kluctl Jinja2 templating.
  # Grafana alert rules and dashboard legendFormat fields contain {{ }}
  # which kluctl interprets as Jinja2 delimiters and chokes on.
  config.kluctl.files.".templateignore" = ''
    default/easykubenix.yaml
  '';

  # ai-coding namespace (used by ai-coding-tools module)
  config.kubernetes.objects.ai-coding = {
    Namespace.ai-coding = {
      metadata.labels =
        managed
        // {
          name = "ai-coding";
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
    };
  };
}
