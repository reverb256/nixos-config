# XMRig Proxy Module
# Stratum proxy for Monero/RandomX CPU mining
# https://github.com/xmrig/xmrig-proxy
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.xmrig-proxy;
in {
  options.services.xmrig-proxy = {
    enable = lib.mkEnableOption "XMRig Stratum proxy for CPU mining";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.xmrig-proxy;
      description = "XMRig proxy package to use";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "xmrig-proxy";
      description = "User account to run xmrig-proxy";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "xmrig-proxy";
      description = "Group account to run xmrig-proxy";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/xmrig-proxy";
      description = "Data directory for xmrig-proxy";
    };

    config = lib.mkOption {
      type = lib.types.str;
      description = "xmrig-proxy configuration (JSON format)";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports for xmrig-proxy";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 3333;
      description = "Stratum port to listen on";
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = "API port for monitoring";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = {
      group = cfg.group;
      isSystemUser = true;
      description = "XMRig proxy service user";
    };

    users.groups.${cfg.group} = {};

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    # Write config file
    environment.etc."xmrig-proxy/config.json".text = cfg.config;

    # Firewall
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.listenPort ];
      allowedUDPPorts = [ cfg.listenPort ];
    };

    # Note: Add Prometheus scraping in monitoring setup
    # The proxy provides API at http://localhost:${toString cfg.apiPort}/1/summary

    # Systemd service
    systemd.services.xmrig-proxy = {
      description = "XMRig Stratum Proxy for CPU Mining";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        WorkingDirectory = cfg.dataDir;

        ExecStart = "${cfg.package}/bin/xmrig-proxy --config /etc/xmrig-proxy/config.json --no-color";

        Restart = "on-failure";
        RestartSec = "10s";

        # Hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];

        # Resource limits
        MemoryLimit = "512M";
        CPUQuota = "200%";
      };

      # Graceful shutdown
      serviceConfig.ExecStop = "${pkgs.coreutils}/bin/kill -SIGTERM $MAINPID";
    };
  };
}
