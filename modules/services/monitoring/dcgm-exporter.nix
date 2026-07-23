# NVIDIA DCGM Exporter - GPU hardware error tracking (ECC, PCIe, power limits)
# Runs as podman container pulling nvidia/dcgm-exporter image
# Deployed on Zephyr, Nexus, Forge (hosts with NVIDIA GPUs)
{ config, lib, pkgs, ... }: let
  cfg = config.services.monitoring.dcgm-exporter;
  inherit (lib) mkEnableOption mkOption types mkIf;
  port = 9401; # Different from nvidia-smi exporter on 9400
in {
  options.services.monitoring.dcgm-exporter = {
    enable = mkEnableOption "NVIDIA DCGM GPU hardware error telemetry exporter";
    listenAddress = mkOption { type = types.str; default = "127.0.0.1"; };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers.dcgm-exporter = {
      image = "nvidia/dcgm-exporter:4.2.0-3.7.3-ubuntu24.04";
      ports = [ "${cfg.listenAddress}:${toString port}:9400" ];
      environment = {
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "all";
      };
      extraOptions = [
        "--gpus=all"
        "--runtime=nvidia"
      ];
    };

    # Scrape target for Prometheus (add to prometheus scrape config)
    services.prometheus.scrapeConfigs = [{
      job_name = "dcgm";
      static_configs = [{
        targets = [ "${cfg.listenAddress}:${toString port}" ];
        labels = { exporter = "dcgm"; };
      }];
    }];

    # Add DCGM alert rules
    services.prometheus.rules = let
      mkRule = name: alert: ''
        groups:
          - name: ${name}
            interval: 30s
            rules:
${builtins.concatStringsSep "\n" (map (a: "            ${builtins.toJSON a}") alert)}
      '';
    in [ (mkRule "dcgm" [
      {
        alert = "GpuEccCorrectedRate";
        expr = "rate(DCGM_FI_DEV_ECC_CORRECTED[5m]) > 0.1";
        for = "5m";
        labels = { severity = "critical-paging"; };
        annotations = {
          summary = "High ECC correctable rate on GPU {{ $labels.gpu }}";
          description = "ECC corrected errors exceeding 0.1/s for 5 minutes. Memory degradation possible.";
        };
      }
      {
        alert = "GpuPcieReplayCount";
        expr = "rate(DCGM_FI_DEV_PCIE_REPLAY_COUNT[5m]) > 0.5";
        for = "5m";
        labels = { severity = "critical"; };
        annotations = {
          summary = "High PCIe replay count on GPU {{ $labels.gpu }}";
          description = "PCIe replay errors exceeding 0.5/s for 5 minutes. Check slot seating.";
        };
      }
    ]) ];

    networking.firewall.allowedTCPPorts = [ port ];
  };
}
