{
  config,
  lib,
  pkgs,
  ...
}: let
  syncScript = pkgs.writeShellApplication {
    name = "opencode-sync-models";
    runtimeInputs = [
      pkgs.python3
      pkgs.python3Packages.requests
    ];
    text = ''
      exec ${./opencode-sync-models.py} "$@"
    '';
  };
in {
  options.services.opencode-sync = {
    enable = lib.mkEnableOption "OpenCode model sync from AI Gateway";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      example = "1h";
      description = "How often to sync models from gateway";
    };

    user = lib.mkOption {
      type = lib.types.str;
      example = "j_kro";
      description = "User to run sync as";
    };
  };

  config = lib.mkIf config.services.opencode-sync.enable {
    systemd.timers.opencode-sync = {
      description = "Sync OpenCode models from AI Gateway";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnUnitActiveSec = config.services.opencode-sync.interval;
        OnBootSec = "1min";
        Unit = "opencode-sync.service";
      };
    };

    systemd.services.opencode-sync = {
      description = "Sync OpenCode models from AI Gateway";
      serviceConfig = {
        Type = "oneshot";
        User = config.services.opencode-sync.user;
        ExecStart = "${syncScript}/bin/opencode-sync-models";
      };
      environment = {
        PATH = "/run/wrappers/bin:/home/${config.services.opencode-sync.user}/.local/bin:/run/current-system/sw/bin";
      };
    };
  };
}
