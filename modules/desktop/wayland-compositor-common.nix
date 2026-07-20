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
    # Guarded because the noctalia NixOS module may not be loaded on all
    # configurations. When it is absent, skip the noctalia integration
    # entirely so niri can still be enabled without the extra flake input.
    } // lib.optionalAttrs noctaliaEnabled {
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
    # 2026-07-10: run noctalia INSIDE the logind session scope, NOT as a
    # detached `systemd --user` service. The BrightnessService resolves its
    # controllable displays via logind `GetSessionByPID`. A user-service PID
    # is not "in" any logind session, so logind returns `NoSessionForPID`
    # and noctalia bails out of brightness probing entirely — every slider
    # grays out (DDC + SDR alike). Launching noctalia as a niri
    # `spawn-at-startup` child (see modules/home-manager/niri-config.nix)
    # makes it a descendant of niri, which lives in `session-*.scope`, so
    # the logind lookup resolves and BrightnessService actually probes
    # ddcutil and the SDR backend.
    programs.noctalia.systemd.enable = mkForce false;

    # The patched daemon (desktop.noctalia.daemonPackage) now owns the
    # brightness backends natively: DDC/CI via ddcutil for DP-* and the
    # compositor-driven SDR backend (niri IPC) for HDMI-A-2. The old
    # wrapper intercepted brightness verbs and routed them to
    # scripts/brightness-router.sh, which (a) could not drive SDR and
    # (b) had an arg-order bug (`brightness-set <conn> <pct>` swapped
    # them). Drop the interception entirely — pass every verb through to
    # the daemon. This keeps `noctalia msg volume-up`, panel toggles, etc.
    # working while letting the daemon handle brightness natively.
    programs.noctalia.package = lib.mkForce (pkgs.writeShellScriptBin "noctalia" ''
      exec ${lib.getExe config.desktop.noctalia.daemonPackage} "$@"
    '');

    # Point the daemon at the system-managed TOML (/etc/noctalia/config.toml,
    # symlinked into /etc/static). Previously set on the systemd unit's
    # environment; with the user service gone we set it session-wide so the
    # spawn-at-startup child inherits it.
    environment.sessionVariables.NOCTALIA_CONFIG_HOME = "/etc";
  };
}
