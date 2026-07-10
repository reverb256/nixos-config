{
  config,
  lib,
  pkgs,
  inputs,
  options,
  ...
}:

let
  inherit (lib) mkIf mkDefault mkForce mkOption types;
  noctaliaEnabled = options ? programs.noctalia.enable;
in {
  options = {
    desktop.noctalia.daemonPackage = mkOption {
      type = types.package;
      default = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = "inputs.noctalia.packages.\\${pkgs.stdenv.hostPlatform.system}.default";
      description = "Noctalia daemon package (overridable for patched versions)";
    };
  };

  config = mkIf (config.programs.niri.enable or false) {

    # ── SSH agent conflict resolution ──────────────────────────────────
    # REQUIRED — NixOS asserts that `programs.ssh.startAgent = true` (set
    # globally by modules/system/distributed-builds.nix for cluster-wide
    # distributed builds) cannot coexist with `services.gnome.gcr-ssh-agent.enable`.
    services.gnome.gcr-ssh-agent.enable = mkDefault false;

    # ── noctalia v5: install + systemd-managed daemon ─────────────────
    # 2026-07-07 refactor: moved off the hand-rolled
    # `systemd.user.services.noctalia` block in modules/home-manager/niri-config.nix
    # to upstream's first-class option. The noctalia NixOS module
    # (`nix/nixos-module.nix` in the flake) ships
    # `programs.noctalia.systemd.enable` which registers
    # `systemd.user.services.noctalia` with `Restart = "on-failure"`
    # wired to `graphical-session.target` -- the canonical NixOS pattern
    # we want here.
    # UPSTREAM'S ExecStart DOES NOT source `/etc/uwsm/env-niri` (which
    # exports QT_WAYLAND_DISABLE_WINDOWDECORATION and GST_PLUGIN_PATH
    # -- both load-bearing for noctalia's Qt rendering + media plumbing).
    # We override only that one field with mkForce to keep upstream's
    # restart + target wiring intact while layering in uwsm env +
    # NIRI_SOCKET discovery. Keeping this here (not per-host) so every
    # niri-enabled host (zephyr/forge/sentry) gets it consistently.
    # mkDefault lets per-host `lib.mkForce false` opt out cleanly --
    # e.g. a Vulkan AI inference machine on hosts/sentry that wants
    # niri but not the desktop shell daemon.
    programs.noctalia.enable = mkDefault true;
    programs.noctalia.systemd.enable = mkDefault true;
    # After: list values merge across module boundaries, so adding our
    # own entries composes with upstream's graphical-session.target
    # ordering. Pipewire + wireplumber services must be active before
    # noctalia starts so the v5 audio plugin can probe wireplumber on
    # boot -- otherwise the audio plugin init hangs / silently fails
    # (the exact regression the user reported on "volume keys dead").
    systemd.user.services.noctalia.unitConfig.After = [
      "pipewire.service"
      "wireplumber.service"
    ];
    systemd.user.services.noctalia.serviceConfig.ExecStart = mkForce (
      pkgs.writeShellScript "noctalia-launch" ''
        #!/usr/bin/env bash
        set -a
        . /etc/uwsm/env-niri
        set +a
        # 2026-07-07: a bare systemd --user ExecStart does NOT inherit
        # the user session's `NIRI_SOCKET`. uwsm finalize blocks on
        # `UWSM_WAIT_VARNAMES=NIRI_SOCKET` if it's empty. Discover the
        # runtime niri socket (PID-suffixed, dynamic) and export it.
        for s in /run/user/$(id -u)/niri.wayland-*.sock; do
          [ -S "$s" ] && export NIRI_SOCKET="$s" && break
        done
        # Mirror upstream's `lib.getExe cfg.package` so we pick up
        # whatever `mainProgram`/multi-bin rewire happens upstream
        # rather than hard-coding `/bin/noctalia`. If noctalia ever
        # renames its binary, this stays correct.
        exec ${lib.getExe config.programs.noctalia.package}
      ''
    );

    # ── noctalia v5: wrapper as the package so it shadows the daemon ──
    # 2026-07-07 refactor: the prior approach installed a `noctalia` wrapper
    # via `environment.systemPackages` while the upstream NixOS module also
    # installed the daemon package as `programs.noctalia.package`. Both
    # produced `bin/noctalia` and the daemon's ELF won the PATH collision,
    # so the brightness intercept never ran (XF86 keys hit the daemon
    # directly, which has no DDC backend for the locked-I2C HDTV and
    # reports "brightness control unavailable"). The fix: override
    # `programs.noctalia.package` to the wrapper derivation. The upstream
    # module then installs ONLY the wrapper (no daemon binary on PATH
    # besides what the wrapper's Nix-store reference exec's into). The
    # wrapper still exec's the real daemon for non-brightness verbs, so
    # `noctalia msg volume-up`, `noctalia msg panel-toggle launcher`,
    # etc. all work; only `brightness-{up,down,get,set}` is intercepted
    # and routed to scripts/brightness-router.sh.
    programs.noctalia.package = lib.mkForce (pkgs.writeShellScriptBin "noctalia" ''
      if [[ "$1" == "msg" ]]; then
        case "$2" in
          brightness-up|brightness-down|brightness-get|brightness-set)
            exec ${./../../scripts/brightness-router.sh} "$2" "''${@:3}"
            ;;
        esac
      fi
      exec ${lib.getExe config.desktop.noctalia.daemonPackage} "$@"
    '');
  };
}
