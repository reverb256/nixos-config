# machines.nix - Nix distributed build farm configuration
# Documentation: https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html
#
# NOTE: This file supersedes /etc/nixos/modules/system/distributed-builds.nix
# The old module will be deprecated once this is fully validated.
#
# Total cluster: 42 cores (16 + 12 + 6 + 8)
# K8s-aware: Conservative allocations preserve control plane stability

[
  # Zephyr - K8s control plane + node (16 cores, must stay stable)
  {
    hostName = "zephyr";
    systems = ["x86_64-linux"];
    sshUser = "j_kro";
    protocol = "ssh-ng";
    maxJobs = 8;  # CONSERVATIVE - apiserver/etcd need CPU
    speedFactor = 8;  # Fast, but not prioritized over K8s
    supportedFeatures = ["kvm" "big-parallel"];
    mandatoryFeatures = [];  # Don't force builds if K8s is busy
  }

  # Nexus - K8s storage worker + NFS (12 cores, needs I/O headroom)
  {
    hostName = "nexus";
    systems = ["x86_64-linux"];
    sshUser = "j_kro";
    protocol = "ssh-ng";
    maxJobs = 6;  # MODERATE - leave cores for NFS/PVC operations
    speedFactor = 5;
    supportedFeatures = ["big-parallel"];
    mandatoryFeatures = [];
  }

  # Forge - K8s multi-GPU worker (6 cores, MIXED NVIDIA/AMD)
  {
    hostName = "forge";
    systems = ["x86_64-linux"];
    sshUser = "j_kro";
    protocol = "ssh-ng";
    maxJobs = 2;  # MINIMAL - GPU pods need CPU, mixed vendor = chaos
    speedFactor = 2;  # Deprioritized - GPUs matter more than builds
    supportedFeatures = ["kvm"];  # No big-parallel - keep resources for GPU
    mandatoryFeatures = [];
  }

  # Sentry - K8s monitoring worker (8 cores)
  {
    hostName = "sentry";
    systems = ["x86_64-linux"];
    sshUser = "j_kro";
    protocol = "ssh-ng";
    maxJobs = 4;  # LIGHT - Prometheus/Grafana/Loki need CPU
    speedFactor = 4;
    supportedFeatures = ["big-parallel"];
    mandatoryFeatures = [];
  }
]
