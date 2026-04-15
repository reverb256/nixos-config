# Hermes Agent dashboard module
#
# Runs `hermes dashboard` as a systemd service alongside the gateway.
# Uses a .pth file to inject the web dist path at Python startup.
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

  # .pth file that patches hermes_cli.web_server.WEB_DIST at startup
  webDistPth = pkgs.writeTextFile {
    name = "hermes-web-dist-patch";
    destination = "/${pkgs.python311.sitePackages}/zzz_hermes_web_dist.pth";
    # .pth files can contain Python code if they start with "import "
    text = "import hermes_cli.web_server as _hws; _hws.WEB_DIST = __import__('pathlib').Path('${hermes-web-dist}')";
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

    # Activation: pip install fastapi into a dedicated venv
    system.activationScripts."hermes-dashboard-setup" = lib.stringAfter [ "hermes-agent-setup" ] ''
      DASHBOARD_VENV="${hermesCfg.stateDir}/.hermes/dashboard-venv"
      if [ ! -d "$DASHBOARD_VENV" ]; then
        echo "Creating dashboard venv with fastapi..."
        ${pkgs.python311}/bin/python3.11 -m venv "$DASHBOARD_VENV" 2>/dev/null || true
        chown -R ${hermesCfg.user}:${hermesCfg.group} "$DASHBOARD_VENV" 2>/dev/null || true
        sudo -u ${hermesCfg.user} "$DASHBOARD_VENV/bin/pip" install --quiet \
          'fastapi>=0.104.0,<1' 'uvicorn[standard]>=0.24.0,<1' 2>/dev/null || true
      fi
    '';

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
        # Add fastapi venv + web_dist patch to python path
        PYTHONPATH = lib.concatStringsSep ":" [
          "${hermesCfg.stateDir}/.hermes/dashboard-venv/lib/python3.11/site-packages"
          "${webDistPth}/${pkgs.python311.sitePackages}"
        ];
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
