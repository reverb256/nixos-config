# OpenClaw Gateway Container Module
# Provides a properly configured OpenClaw gateway container via Podman
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.openclaw-gateway;
in {
  options.services.openclaw-gateway = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable OpenClaw gateway container";
    };

    token = mkOption {
      type = types.str;
      default = "";
      description = "Authentication token for the gateway";
    };

    port = mkOption {
      type = types.int;
      default = 18090;
      description = "Port for the gateway";
    };

    workspaceDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/workspace";
      description = "Host directory to mount as workspace";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/state";
      description = "Host directory for OpenClaw state";
    };

    image = mkOption {
      type = types.str;
      default = "docker.io/alpine/openclaw:latest";
      description = "Container image to use";
    };

    memory = mkOption {
      type = types.str;
      default = "8G";
      description = "Memory limit for the container";
    };
  };

  config = mkIf cfg.enable {
    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 root root -"
      "d ${cfg.workspaceDir} 0755 root root -"
    ];

    # Create the container using oci-containers
    virtualisation.oci-containers.containers.openclaw-gateway = {
      image = cfg.image;

      ports = ["127.0.0.1:${toString cfg.port}:${toString cfg.port}"];

      volumes = [
        "${cfg.stateDir}:/home/node/.openclaw"
        "${cfg.workspaceDir}:/workspace"
      ];

      environment = {
        OPENCLAW_GATEWAY_TOKEN = cfg.token;
      };

      extraOptions = [
        "--memory=${cfg.memory}"
        "--security-opt=label=disable"
      ];
    };

    # Open firewall port (localhost only)
    networking.firewall.allowedTCPPorts = mkIf (cfg.port != 18090) [cfg.port];
  };
}
