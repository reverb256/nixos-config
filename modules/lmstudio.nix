# LM Studio - Local LLM Interface using nixpkgs package
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.lmstudio;

  lmstudio = pkgs.lmstudio;

  lms-wrapped = pkgs.writeShellScriptBin "lms" ''
    #!/bin/bash
    exec "${lmstudio}/bin/lms" "$@"
  '';

  lmstudio-wrapped = pkgs.writeShellScriptBin "lm-studio" ''
    #!/bin/bash
    exec "${lmstudio}/bin/lm-studio" "$@"
  '';
in {
  options.services.lmstudio = {
    enable = mkEnableOption "LM Studio - Local LLM Interface";

    package = mkOption {
      type = types.package;
      default = lmstudio;
      description = "LM Studio package from nixpkgs";
    };

    enableGui = mkOption {
      type = types.bool;
      default = true;
      description = "Enable LM Studio GUI application";
    };

    enableServer = mkOption {
      type = types.bool;
      default = true;
      description = "Enable headless API server";
    };

    port = mkOption {
      type = types.port;
      default = 1234;
      description = "Port for LM Studio local server API";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host for LM Studio local server";
    };

    modelsDir = mkOption {
      type = types.str;
      default = "/var/lib/lmstudio/models";
      description = "Directory containing model files";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/lmstudio/data";
      description = "LM Studio data directory";
    };

    user = mkOption {
      type = types.str;
      default = "root";
      description = "User to run the server as";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [lms-wrapped]
      ++ optionals cfg.enableGui [lmstudio-wrapped];

    systemd.tmpfiles.settings.lmstudio = {
      "${cfg.modelsDir}" = {
        d = {
          user = cfg.user;
          group = cfg.user;
          mode = "0755";
        };
      };
      "${cfg.dataDir}" = {
        d = {
          user = cfg.user;
          group = cfg.user;
          mode = "0755";
        };
      };
    };

    systemd.services.lmstudio = mkIf cfg.enableServer {
      description = "LM Studio Local LLM Server";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Restart = "on-failure";
        RestartSec = "10s";
        ExecStart = "${lms-wrapped}/bin/lms server start --host ${cfg.host} --port ${toString cfg.port}";
        Environment = [
          "HOME=/var/lib/${cfg.user}"
          "XDG_DATA_HOME=${cfg.dataDir}"
        ];
      };
    };

    networking.firewall.interfaces.lo.allowedTCPPorts = mkIf cfg.enableServer [cfg.port];
  };
}
