# machines.nix - Nix distributed build farm configuration
# Format: https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html
#
# Each line: [protocol://]user@host system ssh-key max-jobs speed-factor supported-features mandatory-features
# Note: Empty fields use defaults, - means "not specified"

# Zephyr - K8s control plane + node (16 cores, must stay stable)
# CONSERVATIVE maxJobs (apiserver/etcd need CPU headroom)
ssh-ng://j_kro@zephyr x86_64-linux - 8 8 kvm,big-parallel -

# Nexus - K8s storage worker + NFS (12 cores, needs I/O headroom)  
# MODERATE maxJobs (leave cores for NFS/PVC operations)
ssh-ng://j_kro@nexus x86_64-linux - 6 5 big-parallel -

# Forge - K8s multi-GPU worker (6 cores, MIXED NVIDIA/AMD)
# MINIMAL maxJobs (GPU pods need CPU, mixed vendor = chaos)
ssh-ng://j_kro@forge x86_64-linux - 2 2 kvm -

# Sentry - K8s monitoring worker (8 cores)
# LIGHT maxJobs (Prometheus/Grafana/Loki need CPU)
ssh-ng://j_kro@sentry x86_64-linux - 4 4 big-parallel -
