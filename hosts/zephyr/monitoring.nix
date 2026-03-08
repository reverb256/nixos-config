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
  # Note: GPU metrics are already being exported via nvidia-exporter on port 9400
  # This is configured in the main configuration.nix via hardware.profiles.nvidia

  # Mining exporter (for mining operations on zephyr)
  # Note: Mining metrics are exported via the mining-exporter module
  # Enable if you want to track hashrate, power usage, etc.
  # services.mining-exporter.enable = true;
}
