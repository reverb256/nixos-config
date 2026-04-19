{ pkgs, ... }:
{
  # ai-coding namespace (used by ai-coding-tools module)
  config.kubernetes.objects.ai-coding = {
    Namespace.ai-coding = {
      metadata.labels = {
        name = "ai-coding";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };
  };
}