# cAdvisor - Container Advisor
# Metrics collector for Docker/Podman containers
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.cadvisor;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.services.cadvisor = {
    enable = mkEnableOption "cAdvisor container metrics collector";

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to listen on";
    };

    port = mkOption {
      type = types.port;
      default = 9180;
      description = "Port for cAdvisor HTTP server";
    };

    dockerEndpoint = mkOption {
      type = types.str;
      default = "unix:///var/run/docker.sock";
      description = "Docker endpoint (socket or TCP)";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.cadvisor = {
      description = "cAdvisor container metrics collector";
      wantedBy = [ "multi-user.target" ];
      after = [
        "docker.service"
        "podman.service"
        "network.target"
      ];
      documentation = [ "https://github.com/google/cadvisor" ];

      serviceConfig = {
        Type = "simple";
        User = "cadvisor";
        Group = "cadvisor";
        ExecStart = ''
          ${pkgs.cadvisor}/bin/cadvisor \
            --listen_address=${cfg.listenAddress}:${toString cfg.port} \
            --docker=${cfg.dockerEndpoint} \
            --store_duration=2m \
            --housekeeping_interval=10s \
            --disable_metrics=accelerator,cpu_topology,disk,diskIO,memory_numa,memory_tcp,process,referenced_memory,resctrl,sched,tcp,udp,advtcp \
            --allow_security_classes=false \
            --v=2
        '';

        Restart = "on-failure";
        RestartSec = "10s";
        StandardOutput = "journal";
        StandardError = "journal";

        CapabilityBoundingSet = [
          "CAP_DAC_OVERRIDE"
          "CAP_SYS_ADMIN"
          "CAP_NET_RAW"
        ];
        NoNewPrivileges = false;
        PrivateDevices = false;
        PrivateTmp = false;
        ProtectSystem = "false";
        ProtectHome = true;
        ReadWritePaths = [
          "/var/run/docker.sock"
          "/var/run/podman/podman.sock"
        ];
        ReadOnlyPaths = [
          "/sys/fs/cgroup"
          "/proc"
          "/sys"
        ];

        Environment = [
          "HOSTNAME=${config.networking.hostName}"
        ];
      };
    };

    users.users.cadvisor = {
      isSystemUser = true;
      group = "cadvisor";
      description = "cAdvisor container metrics collector";
    };
    users.groups.cadvisor = { };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];
  };
}
