# Cluster-scoped Kubernetes resources
# PriorityClasses and other non-namespaced resources
{ pkgs, ... }:
{
  config.kubernetes.objects.none = {
    # Mining priority classes — preempted by AI/gaming workloads
    PriorityClass.mining-low = {
      value = -10;
      preemptionPolicy = "PreemptLowerPriority";
      globalDefault = false;
      description = "Low priority for crypto mining workloads";
    };
    PriorityClass.preemptible-mining = {
      value = -1000;
      preemptionPolicy = "PreemptLowerPriority";
      globalDefault = false;
      description = "Low priority for mining workloads - preempted by AI/gaming workloads";
    };
  };
}
