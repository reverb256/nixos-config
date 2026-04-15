# Hermes Agent dashboard module
#
# Builds the web frontend (Vite SPA) and runs `hermes dashboard` as a
# separate systemd service alongside the gateway.
#
# The gateway service (hermes-agent.service) is provided by the official
# NixOS module. This module ONLY adds the web dashboard.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.services.hermes-dashboard;
  hermesCfg = config.services.hermes-agent;

  # Build the web SPA from the same source as the hermes-agent flake input
  hermes-web-dist = pkgs.callPackage ../../packages/hermes-web-dist.nix {
    hermesSrc = inputs.hermes-agent;
  };

in {
  options.services.hermes-dashboard = {
    enable = lib.mkEnableOption "Hermes Agent web dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9119;
      description = "Port for the web dashboard.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Host to bind the dashboard to.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the dashboard port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Require the gateway to be enabled too
    services.hermes-agent.enable = lib.mkDefault true;

    # Dashboard systemd service
    systemd.services.hermes-dashboard = {
      description = "Hermes Agent Web Dashboard";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "hermes-agent.service" ];
      wants = [ "network-online.target" ];
      requires = [ "hermes-agent.service" ];

      environment = {
        HOME = hermesCfg.stateDir;
        HERMES_HOME = "${hermesCfg.stateDir}/.hermes";
        HERMES_MANAGED = "true";
        HERMES_WEB_DIST = "${hermes-web-dist}";
      };

      path = [
        hermesCfg.package
        pkgs.nodejs_20
        pkgs.bash
        pkgs.coreutils
      ];

      serviceConfig = {
        User = hermesCfg.user;
        Group = hermesCfg.group;
        WorkingDirectory = hermesCfg.workingDirectory;

        ExecStart = "${hermesCfg.package}/bin/hermes dashboard --host ${cfg.host} --port ${toString cfg.port} --insecure --no-open";

        Restart = "always";
        RestartSec = 5;

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = false;
        ReadWritePaths = [ hermesCfg.stateDir ];
        PrivateTmp = true;
      };
    };

    # Open firewall
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];
  };
}
