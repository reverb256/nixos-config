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
}
