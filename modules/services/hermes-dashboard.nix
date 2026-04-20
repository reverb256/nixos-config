# Hermes Agent dashboard module
#
# Runs `hermes dashboard` as a systemd service alongside the gateway.
# Uses a wrapper package that injects the built web_dist into the hermes_cli
# package directory via Python's namespace package mechanism.
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

  # Create a wrapper package with web_dist injected into hermes_cli
  hermes-with-web = pkgs.callPackage ../../packages/hermes-with-web.nix {
    hermes-pkg = hermesCfg.package;
    web-dist = hermes-web-dist;
  };


in
{
  options.services.hermes-dashboard = {
    enable = lib.mkEnableOption "Hermes Agent web dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9119;
      description = "Port for the web dashboard.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host to bind the dashboard to.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
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
      after = [
        "network-online.target"
        "hermes-agent.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "hermes-agent.service" ];

      environment = {
        HOME = hermesCfg.stateDir;
        HERMES_HOME = "${hermesCfg.stateDir}/.hermes";
        HERMES_MANAGED = "true";
      };

      path = [
        hermes-with-web
        pkgs.bash
        pkgs.coreutils
      ];

      serviceConfig = {
        User = hermesCfg.user;
        Group = hermesCfg.group;
        WorkingDirectory = hermesCfg.workingDirectory;

        # Use the wrapper package which has web_dist injected
        ExecStart = "${hermes-with-web}/bin/hermes dashboard --host ${cfg.host} --port ${toString cfg.port} --insecure --no-open";

        Restart = "always";
        RestartSec = 5;

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
