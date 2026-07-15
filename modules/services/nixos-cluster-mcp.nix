{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.nixos-cluster-mcp;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.nixos-cluster-mcp = {
    enable = mkEnableOption "NixOS Cluster MCP SSE daemon";

    port = mkOption {
      type = types.port;
      default = 8081;
      description = "SSE listen port";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "SSE listen address (use 127.0.0.1 for localhost-only)";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.nixos-cluster-mcp;
      defaultText = "pkgs.nixos-cluster-mcp";
      description = "The nixos-cluster-mcp package to use";
    };

    nodesFile = mkOption {
      type = types.path;
      default = "/etc/nixos-cluster-mcp/nodes.json";
      description = "Path to the node registry JSON file";
    };
  };

  config = mkIf cfg.enable {
    # Ensure the node registry directory exists
    systemd.tmpfiles.rules = [
      "d /etc/nixos-cluster-mcp 0750 root root -"
    ];

    environment.etc."nixos-cluster-mcp/nodes.json" = {
      mode = "0640";
      text = builtins.toJSON [
        {
          name = "nexus";
          host = "10.1.1.120";
          user = "j_kro";
          build_host = "nexus";
          allow_deploy = true;
          allow_build = true;
          allow_rollback = true;
          mining_host = true;
          tags = ["primary-server" "gateway" "build-host"];
        }
        {
          name = "zephyr";
          host = "10.1.1.110";
          user = "j_kro";
          build_host = "nexus";
          allow_deploy = true;
          allow_build = true;
          allow_rollback = true;
          mining_host = true;
          tags = ["workstation" "control-plane" "gaming"];
        }
        {
          name = "forge";
          host = "10.1.1.130";
          user = "j_kro";
          build_host = "nexus";
          allow_deploy = true;
          allow_build = true;
          allow_rollback = true;
          mining_host = true;
          tags = ["gpu-compute" "mining"];
        }
        {
          name = "sentry";
          host = "10.1.1.140";
          user = "j_kro";
          build_host = "nexus";
          allow_deploy = true;
          allow_build = true;
          allow_rollback = true;
          mining_host = false;
          tags = ["monitoring" "rocm-inference"];
        }
      ];
    };

    systemd.services.nixos-cluster-mcp = {
      description = "NixOS Cluster MCP Server (SSE daemon)";
      after = ["network-online.target" "tmpfiles-setup.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        User = "nixos-cluster-mcp";
        Group = "nixos-cluster-mcp";

        ExecStart = ''
          ${cfg.package}/bin/nixos-cluster-mcp \
            --transport sse \
            --host ${cfg.host} \
            --port ${toString cfg.port}
        '';

        Environment = [
          "NIXOS_MCP_NODES=${cfg.nodesFile}"
        ];

        # Lifecycle — catch crashes but don't restart if failing fast
        Restart = "on-failure";
        RestartSec = "5";
        StartLimitIntervalSec = "300";
        StartLimitBurst = "5";

        # Watchdog: if server stops sending pings for 120s → SIGKILL + restart
        WatchdogSec = "120";

        # Resource limits — bounded so a runaway build can't OOM nexus
        MemoryMax = "1G";
        CPUQuota = "80%";

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        ReadWritePaths = ["/tmp" "/var/lib/nixos-cluster-mcp"];

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Firewall: open the SSE port (default 8081)
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];
  };
}
