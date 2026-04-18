{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.brain-critic;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;

  criticScript = pkgs.writeShellScriptBin "brain-critic-run" ''
    set -euo pipefail
    exec ${pkgs.python3}/bin/python3 ${cfg.scriptPath} \
      "$@"
  '';
in
{
  options.services.brain-critic = {
    enable = mkEnableOption "Brain Critic — Reflexion agent for session extractions";

    scriptPath = mkOption {
      type = types.path;
      default = /home/j_kro/brain/scripts/critic.py;
      description = "Path to the critic.py script";
    };

    gatewayUrl = mkOption {
      type = types.str;
      default = "http://nexus:8080";
      description = "Inference gateway URL for reflection generation";
    };

    gatewayModel = mkOption {
      type = types.str;
      default = "qwen3.5-35b-a3b";
      description = "Model to use for reflection at the gateway";
    };

    brainRoot = mkOption {
      type = types.str;
      default = "/home/j_kro/brain";
      description = "Root directory of the brain system";
    };

    user = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User to run the critic service as";
    };

    group = mkOption {
      type = types.str;
      default = "users";
      description = "Group to run the critic service as";
    };

    schedule = mkOption {
      type = types.str;
      default = "23:00";
      description = "When to run the critic (systemd timer calendar format)";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.brain-critic = {
      description = "Brain Critic — Reflexion agent for session extractions";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${criticScript}/bin/brain-critic-run";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.brainRoot;

        Environment = [
          "BRAIN_ROOT=${cfg.brainRoot}"
          "BRAIN_GATEWAY_URL=${cfg.gatewayUrl}"
          "BRAIN_GATEWAY_MODEL=${cfg.gatewayModel}"
        ];

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "${cfg.brainRoot}/queues"
          "${cfg.brainRoot}/learning"
        ];
        ReadOnlyPaths = [
          "${cfg.brainRoot}/scripts"
        ];
      };
    };

    systemd.timers.brain-critic = {
      description = "Daily Brain Critic reflection run";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "5m";
        Unit = "brain-critic.service";
      };
    };
  };
}
