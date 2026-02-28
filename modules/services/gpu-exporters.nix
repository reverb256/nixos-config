# GPU Metrics Exporters for Prometheus
# Exports NVIDIA GPU metrics for cluster monitoring
# Uses prometheus-nvidia-gpu-exporter (nvidia-smi based)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.gpu-exporters;
in
{
  options.services.gpu-exporters = {
    enable = lib.mkEnableOption "NVIDIA GPU metrics exporters";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9400;
      description = "Port for NVIDIA GPU exporter";
    };
  };

  config = lib.mkIf cfg.enable {
    # NVIDIA GPU Exporter
    systemd.services.prometheus-nvidia-gpu-exporter = {
      description = "Prometheus NVIDIA GPU Metrics Exporter";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];

      serviceConfig = {
        Type = "simple";
        User = "nvidia-gpu-exporter";
        Group = "nvidia-gpu-exporter";
        DynamicUser = true;
        ExecStart = "${pkgs.prometheus-nvidia-gpu-exporter}/bin/nvidia_gpu_exporter --web.listen-address 127.0.0.1:${toString cfg.port}";

        Restart = "always";
        RestartSec = "10s";
        StandardOutput = "journal";
        StandardError = "journal";

        # Security hardening from upstream module
        CapabilityBoundingSet = "";
        DeviceAllow = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = false;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        UMask = "0077";
        WorkingDirectory = "/tmp";
      };
    };

    # Create user/group for exporter
    users.users.nvidia-gpu-exporter = {
      isSystemUser = true;
      group = "nvidia-gpu-exporter";
    };
    users.groups.nvidia-gpu-exporter = {};

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
