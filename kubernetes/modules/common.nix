{ pkgs, ... }:
{
  config.kubernetes.objects.none = {
    PriorityClass.mining-low = {
      value = -10;
      preemptionPolicy = "PreemptLowerPriority";
      globalDefault = false;
      description = "Low priority for crypto mining workloads";
    };
    PriorityClass.preemptible-mining = {
      value = -20;
      preemptionPolicy = "PreemptLowerPriority";
      globalDefault = false;
      description = "Preemptible priority for mining - evicted by any higher priority workload";
    };
  };

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
