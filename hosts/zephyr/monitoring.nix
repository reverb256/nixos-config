# Zephyr Monitoring Configuration
{...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # Node exporter for system metrics (CPU, memory, disk, network)
  services.monitoring.node-exporter.enable = true;

  # NFS server metrics exporter (zephyr exports /etc/nixos to cluster)
  services.monitoring.nfs-exporter.enable = true;

  # Redis exporter for AI Gateway cache metrics
  services.monitoring.redis-exporter.enable = true;

  # SMART exporter for disk health monitoring
  services.monitoring.smart-exporter.enable = true;

  # GPU metrics exporter (NVIDIA RTX 3090 + 3060 Ti)
  services.gpu-exporters.enable = true;
  services.gpu-exporters.nvidia.enable = true;

  # Mining exporter (for mining operations on zephyr)
  # Track hashrate, power usage, shares accepted/rejected
  services.mining-exporter.enable = true;
}
