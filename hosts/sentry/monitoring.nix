# Sentry Monitoring Configuration
{ config, pkgs, ... }: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # Node exporter for system metrics
  services.monitoring.node-exporter.enable = true;

  # GPU exporters - disabled (no ROCm/rocm-smi on this monitoring host)
  # Note: Sentry has AMD GPU for graphics but not ROCm for GPU monitoring
  services.gpu-exporters.enable = false;

  # Mining exporter for CPU mining metrics
  services.mining-exporter.enable = true;
}
