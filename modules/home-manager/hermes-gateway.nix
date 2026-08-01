# Hermes Agent Gateway — declarative user unit
#
# NOTE (issue #334): hermes is installed via the user nix profile
#   `nix profile install github:NousResearch/hermes-agent`
# so the store path of hermes-agent-env changes on EVERY profile upgrade.
# The previous unit (a plain file at ~/.config/systemd/user/hermes-gateway.service)
# hardcoded a store path and silently went stale — after the 0.18.2 → 0.19.1
# upgrade the unit pinned the old env which lacks hermes_state_common.py,
# and the TUI-spawned gateway crashed with `ModuleNotFoundError` until the
# stale processes were killed.
#
# Fix: exec through %h/.nix-profile, which systemd resolves to
# /home/<user>/.nix-profile — a symlink to the CURRENT profile generation.
# The unit therefore always runs the up-to-date env and self-heals across
# `nix profile upgrade` with zero maintenance. Only the messaging gateway
# (`hermes_cli.main gateway run`) is declared here; the TUI launches its own
# gateway child from its own interpreter.
{
  config,
  lib,
  hostName,
  ...
}: let
  cfg = config.programs.hermes-gateway;
  py = "%h/.nix-profile/bin/python";
in {
  options.programs.hermes-gateway.enable = lib.mkOption {
    type = lib.types.bool;
    default = hostName == "zephyr";
    description = ''
      Whether to run the Hermes messaging gateway as a user systemd service.
      Defaults to true on zephyr (the only host that runs the persistent
      gateway); other hosts run hermes via the TUI on demand.
    '';
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.hermes-gateway = {
      Unit = {
        Description = "Hermes Agent Gateway - Messaging Platform Integration";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
        StartLimitIntervalSec = 0;
      };

      Service = {
        Type = "simple";
        ExecStart = "${py} -m hermes_cli.main gateway run";
        WorkingDirectory = "%h/.hermes";
        Environment = [
          "PATH=%h/.nix-profile/bin:/etc/profiles/per-user/j_kro/bin:%h/.local/bin:%h/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
          "VIRTUAL_ENV=%h/.nix-profile"
          "HERMES_HOME=%h/.hermes"
          # Voice mode + TTS on by default (services.hermes-cli.voiceAutoStart).
          # The TUI gateway reads these as the authoritative voice flags; the
          # wrapped hermes binary injects them too, but this unit runs the
          # unwrapped python directly, so set them here.
          "HERMES_VOICE=1"
          "HERMES_VOICE_TTS=1"
        ];
        Restart = "always";
        RestartSec = 5;
        RestartForceExitStatus = 75;
        KillMode = "mixed";
        KillSignal = "SIGTERM";
        ExecReload = "/bin/kill -USR1 \$MAINPID";
        ExecStopPost = "-${py} -m gateway.cgroup_cleanup";
        TimeoutStopSec = 90;
        StandardOutput = "journal";
        StandardError = "journal";
      };

      Install.WantedBy = ["default.target"];
    };
  };
}
