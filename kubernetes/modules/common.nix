_: let
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

  # Map CRD kinds to their apiVersions. The vendored core
  # apiResources/v1.33.json only covers built-in Kubernetes resources, so
  # any operator CRD must be registered here or easykubenix throws
  # "No apiMapping for <Kind>" when rendering.
  config.kubernetes.apiMappings = {
    PrometheusRule = "monitoring.coreos.com/v1";
    KubeVirt = "kubevirt.io/v1";
  };
}
