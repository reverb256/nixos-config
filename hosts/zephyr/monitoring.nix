# Zephyr Monitoring Configuration
{...}: {
  imports = [
    # ../../modules/services/monitoring/default.nix  # TEMP: Compatibility issues
  ];

  # Node exporter for system metrics
  # services.monitoring.node-exporter.enable = true;

  # NFS server metrics exporter (zephyr exports /etc/nixos to cluster)
  # services.monitoring.nfs-exporter.enable = true;

  # Redis exporter for AI Gateway cache metrics
  # services.monitoring.redis-exporter.enable = true;

  # SMART exporter for disk health monitoring
  # services.monitoring.smart-exporter.enable = true;

  # GPU metrics exporter (NVIDIA RTX 3090 + 3060 Ti)
  # services.gpu-exporters = {
  #   enable = true;
  #   nvidia.enable = true; # RTX 3090 + 3060 Ti
  #   amd.enable = false;
  # };

  # Mining exporter (for mining operations on zephyr)
  # services.mining-exporter.enable = true;
}
