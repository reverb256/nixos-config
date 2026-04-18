{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.brain-research;
  inherit
    (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;

  pythonEnv = pkgs.python3.withPackages (ps: [
    # stdlib only — urllib, json, tempfile are built-in
  ]);
in {
  options.services.brain-research = {
    enable = mkEnableOption "Brain research agent — daily SearXNG search & digest";

    searxngUrl = mkOption {
      type = types.str;
      default = "http://nexus:30888";
      description = "SearXNG API base URL";
    };

    gatewayUrl = mkOption {
      type = types.str;
      default = "http://nexus:8080";
      description = "Inference gateway base URL";
    };

    gatewayModel = mkOption {
      type = types.str;
      default = "qwen3.5-4b";
      description = "Model name on the inference gateway for filtering";
    };

    timerCalendar = mkOption {
      type = types.str;
      default = "*-*-* 06:00:00";
      description = "systemd calendar expression for daily run";
    };

    user = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User to run the research agent as";
    };

    brainRoot = mkOption {
      type = types.str;
      default = "/home/j_kro/brain";
      description = "Root directory of the brain knowledge base";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.brain-research = {
      description = "Brain Research Agent — daily search & digest";
      after = ["network-online.target"];
      wants = ["network-online.target"];

      path = with pkgs; [
        pythonEnv
        curl
        coreutils
      ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = "users";
        WorkingDirectory = cfg.brainRoot;

        ExecStart = "${pythonEnv}/bin/python3 ${cfg.brainRoot}/scripts/research-agent.py";

        Environment = [
          "BRAIN_ROOT=${cfg.brainRoot}"
          "SEARXNG_URL=${cfg.searxngUrl}"
          "GATEWAY_URL=${cfg.gatewayUrl}"
          "GATEWAY_MODEL=${cfg.gatewayModel}"
        ];

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "${cfg.brainRoot}/queues/research-out"
          "${cfg.brainRoot}/raw/articles"
        ];
        ReadOnlyPaths = [
          "${cfg.brainRoot}/scripts"
        ];

        StandardOutput = "journal";
        StandardError = "journal";

        TimeoutStartSec = "300";
      };
    };

    systemd.timers.brain-research = {
      description = "Daily brain research agent timer — 06:00";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.timerCalendar;
        Persistent = true;
        RandomizedDelaySec = "5m";
        AccuracySec = "1m";
      };
    };
  };
}
