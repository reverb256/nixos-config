{ config, lib, pkgs, ... }:

let
  cfg = config.services.hermes-webui;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.hermes-webui = {
    enable = mkEnableOption "Hermes Web UI (nesquena/hermes-webui)";
    port = mkOption { type = types.port; default = 8787; };
    user = mkOption { type = types.str; default = "j_kro"; };
    srcDir = mkOption { type = types.str; default = "/data/projects/own/hermes-webui"; };
  };

  config = mkIf cfg.enable {
    systemd.services.hermes-webui = {
      description = "Hermes Web UI — browser interface for Hermes Agent";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "hermes-agent.service" ];

      environment = {
        HERMES_HOME = "/home/${cfg.user}/.hermes";
        HERMES_WEBUI_HOST = "127.0.0.1";
        HERMES_WEBUI_PORT = toString cfg.port;
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        WorkingDirectory = cfg.srcDir;
        ExecStart = lib.getExe pkgs.python311 + " ${cfg.srcDir}/server.py";
        Restart = "on-failure";
        RestartSec = "5";
      };
    };
  };
}
