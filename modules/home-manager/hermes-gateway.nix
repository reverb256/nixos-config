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
  pkgs,
  hostName,
  pkgs,
  ...
}: let
  cfg = config.programs.hermes-gateway;
  # Self-healing entry point: %h/.nix-profile/bin/hermes is a symlink to the
  # current profile generation, so it tracks `nix profile upgrade` with zero
  # maintenance (the old %h/.nix-profile/bin/python no longer ships in the
  # split-package install — only bin/hermes does).
  hermesBin = "%h/.nix-profile/bin/hermes";

  # PROPER voice support (replaces the old hand-written ~/.local/bin/hermes
  # wrapper + manual GC-root symlink to a nix-built sounddevice).
  #
  # hermesVoice is a real Nix derivation: a shell script that execs the profile's
  # bin/hermes with PYTHONPATH set to nixpkgs' python312Packages.sounddevice.
  # That derivation PATCHES sounddevice's compiled extension to hardcode the
  # portaudio store path at build time (same mechanism nixpkgs uses), so NO
  # LD_LIBRARY_PATH is needed and portaudio resolves from the nix store directly.
  #
  # We use writeShellScriptBin (not makeWrapper) because the hermes binary lives
  # at $HOME/.nix-profile/bin/hermes, which does NOT exist on the remote build
  # host — makeWrapper validates the target at build time and would refuse. A
  # plain script resolves the path at RUNTIME ($HOME), so it works on zephyr.
  #
  # Because hermesVoice is installed via home.packages, sounddevice becomes part
  # of the HM profile closure -> it is GC-safe (never collected) and reproducible.
  # The TUI wrapper (~/.local/bin/hermes) and the gateway unit both exec this
  # derivation, so there is a single source of truth for voice deps.
  hermesVoice = pkgs.writeShellScriptBin "hermes-voice" ''
    export PYTHONPATH="${pkgs.python312Packages.sounddevice}/lib/python3.12/site-packages"
    export HERMES_VOICE=1
    export HERMES_VOICE_TTS=1
    exec "$HOME/.nix-profile/bin/hermes" "$@"
  '';
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
    # Voice-enabled Hermes: a real Nix derivation (hermesVoice, defined in `let`)
    # that wraps the profile's bin/hermes with nixpkgs' portaudio-patched
    # sounddevice on PYTHONPATH. Installing it via home.packages puts sounddevice
    # in the HM profile closure -> GC-safe and reproducible (no manual GC-root).
    home.packages = [ hermesVoice ];

    # TUI entry point: ~/.local/bin/hermes is generated (not hand-written) as the
    # hermesVoice wrapper. It shadows the Layer-3 profile's bin/hermes on PATH, so
    # `hermes` (TUI, /voice on) gets sounddevice. HM owns this file -> self-healing
    # across `home-manager switch`.
    home.file.".local/bin/hermes".source = "${hermesVoice}/bin/hermes-voice";

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
        # Use the voice-enabled wrapper (~/.local/bin/hermes, generated by HM from
        # the hermesVoice derivation). It self-heals across `home-manager switch`
        # and already injects PYTHONPATH (nixpkgs sounddevice) + HERMES_VOICE*.
        ExecStart = "%h/.local/bin/hermes gateway run";
        WorkingDirectory = "%h/.hermes";
        Environment = [
          "PATH=%h/.nix-profile/bin:/etc/profiles/per-user/j_kro/bin:%h/.local/bin:%h/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
          "VIRTUAL_ENV=%h/.nix-profile"
          "HERMES_HOME=%h/.hermes"
          # Voice mode + TTS on by default. The hermesVoice wrapper sets
          # HERMES_VOICE/HERMES_VOICE_TTS too, but declaring them here keeps the
          # gateway authoritative if ever invoked without the wrapper.
          "HERMES_VOICE=1"
          "HERMES_VOICE_TTS=1"
        ];
        Restart = "always";
        RestartSec = 5;
        RestartForceExitStatus = 75;
        KillMode = "mixed";
        KillSignal = "SIGTERM";
        ExecReload = "/bin/kill -USR1 $MAINPID";
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
