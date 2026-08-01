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
# `nix profile upgrade` with zero maintenance. The messaging gateway
# (`hermes_cli.main gateway run`) is declared here (the TUI launches its own
# gateway child from its own interpreter); this module ALSO ships the
# HERMES_TUI_DIR fish conf.d export below (the split-profile install's raw
# bin/hermes lacks the upstream wrapper's TUI wiring).
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
    # The profile installs hermes as SPLIT packages (hermes-agent-env,
    # hermes-tui, hermes-web, hermes-desktop) — bin/hermes is the RAW env
    # script, so the upstream wrapper's HERMES_TUI_DIR wiring (makeWrapper in
    # the `default` package, nix/hermes-agent.nix) is never applied. Without it,
    # `hermes --tui`/`--resume` fails with "TUI workspace is missing from this
    # Hermes checkout". Point it at the profile's stable hermes-tui path (a
    # symlink to the current generation — self-healing across `nix profile
    # upgrade`, same pattern as %h/.nix-profile below).
    #
    # Mechanism: a fish conf.d file, NOT home.sessionVariables. HM's
    # hm-session-vars.fish exports __HM_SESS_VARS_SOURCED, which leaks into the
    # session env; the file's `set -q __HM_SESS_VARS_SOURCED` guard then returns
    # early in every later shell (including fresh ones spawned from the
    # session), skipping ALL `set -gx` lines. conf.d is auto-sourced by EVERY
    # fish instance (interactive + non-interactive) and is immune to that guard
    # leak — same pattern as the existing ~/.config/fish/conf.d/hermes-voice.fish.
    #
    # NOTE: gated on programs.hermes-gateway.enable (the gateway unit) even
    # though it feeds the interactive TUI — zephyr always runs both, so this is
    # the pragmatic single gate. If a host ever disables the gateway but still
    # wants the TUI, move this to an unconditional shared spot.
    home.file.".config/fish/conf.d/hermes-tui.fish".text = ''
      # Hermes profile installs split packages (hermes-agent-env/tui/web/desktop);
      # the raw bin/hermes env script lacks the upstream wrapper's HERMES_TUI_DIR
      # wiring, so the TUI check (_make_tui_argv) falls through to the checkout
      # probe and fails. conf.d is sourced by every fish instance, unlike
      # hm-session-vars (which a leaked __HM_SESS_VARS_SOURCED can skip).
      set -gx HERMES_TUI_DIR '${config.home.homeDirectory}/.nix-profile/lib/hermes-tui'
    '';

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
        # Vault passphrase for the hermes vault feature. Previously injected via
        # an unmanaged plain-file drop-in (vault.conf); folded in so HM owns the
        # whole unit. The `-` prefix tolerates a missing file.
        EnvironmentFile = "-%h/.hermes/hermes-vault-passphrase";
      };

      Install.WantedBy = ["default.target"];
    };
  };
}
