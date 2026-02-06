{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.services.openclaw-node-host;
in {
  options.services.openclaw-node-host = {
    enable = lib.mkEnableOption "OpenClaw Node Host Service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openclaw-gateway or pkgs.openclaw;
      description = "OpenClaw package to use";
    };

    gatewayHost = lib.mkOption {
      type = lib.types.str;
      default = "100.81.182.5";
      description = "Tailscale IP of gateway host (zephyr)";
    };

    gatewayTailscalePort = lib.mkOption {
      type = lib.types.port;
      default = 18790;
      description = "Local port for SSH tunnel to gateway";
    };

    gatewayPort = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "Gateway WebSocket port";
    };

    displayName = lib.mkOption {
      type = lib.types.str;
      default = "Build Node";
      description = "Display name for this node";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-start the node host service";
    };

    execAllowlist = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of allowed commands for exec tool";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "User to run the node host as";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    systemd.tmpfiles.rules = [
      "d /var/lib/openclaw-node 0750 ${cfg.user} ${cfg.user} -"
    ];

    systemd.services.openclaw-node-host = {
      description = "OpenClaw Node Host via SSH Tunnel";
      after = ["network.target" "network-online.target"];
      wants = ["network-online.target"];
      wantedBy = if cfg.autoStart then ["multi-user.target"] else [];

      serviceConfig = {
        Type = "forking";
        Restart = "always";
        RestartSec = "5s";

        ExecStart = "${pkgs.openssh}/bin/ssh -N -L ${toString cfg.gatewayTailscalePort}:127.0.0.1:${toString cfg.gatewayPort} ${cfg.user}@${cfg.gatewayHost}";
        ExecStop = "${pkgs.procps}/bin/pkill -f 'ssh.*${toString cfg.gatewayTailscalePort}:127.0.0.1:${toString cfg.gatewayPort}'";

        RuntimeDirectory = "openclaw-node";
        StateDirectory = "openclaw-node";

        User = cfg.user;
        Group = cfg.user;
      };
    };

    systemd.services.openclaw-node = {
      description = "OpenClaw Node";
      after = ["network.target" "network-online.target" "openclaw-node-host.service"];
      wants = ["openclaw-node-host.service"];
      wantedBy = if cfg.autoStart then ["multi-user.target"] else [];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "5s";
        ExecStart = lib.concatStringsSep " " [
          "${cfg.package}/bin/openclaw"
          "node"
          "run"
          "--host" "127.0.0.1"
          "--port" (toString cfg.gatewayTailscalePort)
          "--display-name" cfg.displayName
        ];
        Environment = [
          "OPENCLAW_STATE_DIR=/var/lib/openclaw-node"
        ];
        RuntimeDirectory = "openclaw-node";
        StateDirectory = "openclaw-node";
        User = cfg.user;
        Group = cfg.user;
      };
    };

    environment.etc."openclaw/exec-approvals.json".text = lib.generators.toJSON {} {
      version = 1;
      allowlist = cfg.execAllowlist;
    };
  };
}
