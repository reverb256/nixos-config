{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  inherit (lib) mkIf mkForce mkOverride mkOption types;
  cfg = config.desktop.zephyr-sdr-brightness;

  # ── Patched noctalia daemon ──────────────────────────────────────────
  # HDMI-A-2 (Samsung TV) now runs HDR natively under niri-unstable, so its
  # brightness backend is set to `normal` (niri owns the output via max_bpc /
  # HDR). The custom niri SDR-brightness patch was dropped 2026-07-25.
  noctalia-patched = pkgs.noctalia.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./../../patches/noctalia-sdr-brightness.patch];
  });

  # ── TOML config for noctalia brightness ──────────────────────────────
  # Written to /etc/noctalia/config.toml. The NOCTALIA_CONFIG_HOME env var
  # (set in the systemd user service environment below) points noctalia's
  # configDir() at /etc/noctalia/. This gives us declarative control over
  # the brightness backend per-monitor without touching the user's home.
  #   - enableDdcSupport: enables the DDC/CI backend for DP-4/5/6
  #   - backend = "normal" on HDMI-A-2: the Samsung TV is HDR-driven natively
  #     by niri-unstable (max_bpc / HDR); niri owns the output. The custom
  #     niri SDR-brightness patch was dropped 2026-07-25.
  noctaliaConfigFile = pkgs.writeText "noctalia-config.toml" ''
    [brightness]
    enable_ddcutil = true

    [brightness.monitor."HDMI-A-2"]
    backend = "normal"
  '';
in {
  options.desktop.zephyr-sdr-brightness = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable noctalia brightness daemon for zephyr's displays (Samsung TV now HDR-driven by niri)";
    };
  };

  config = mkIf cfg.enable {
    # ── Patched niri ────────────────────────────────────────────────────
    # ── Patched noctalia daemon ─────────────────────────────────────────
    # wayland-compositor-common.nix sets desktop.noctalia.daemonPackage as
    # a mkOption (priority 100). mkForce beats the default.
    desktop.noctalia.daemonPackage = mkForce noctalia-patched;
    # Direct systemd user service for patched noctalia daemon
    systemd.user.services.noctalia = {
      description = "Noctalia shell daemon (patched with Sdr brightness backend)";
      wantedBy = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      after = ["graphical-session.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe noctalia-patched}";
        Restart = "on-failure";
        RestartSec = "3";
        Environment = "PATH=/run/current-system/sw/bin";
        # ── cgroup memory caps (2026-07-27 OOM emergency) ───────────────
        # Root cause: on zephyr (31 GB RAM, near-constant pressure from
        # control-plane + gaming + AI + mining), systemd-oomd marked
        # noctalia.service and the alacritty scope as victims at the 90%
        # mem+swap threshold (noctalia peaked at 10.3 GB before kill).
        # Cap the daemon so it self-throttles at 4G / self-kills at 6G
        # BEFORE the global oomd threshold; soften kernel scoring so
        # noctalia is a lower-priority victim if anything bigger pushes
        # the system past limits. OOMPolicy=continue keeps the daemon
        # alive if the kernel sends SIGTERM from oomd pressure (it can
        # then re-arm or gracefully exit on its own terms).
        MemoryHigh = "4G";
        MemoryMax = "6G";
        OOMPolicy = "continue";
        OOMScoreAdjust = -300;
        # 2026-07-27 (code-review G1): prevent thrashing if the Sdr backend
        # persistently leaks past MemoryMax (self-kill → Restart=on-failure
        # → 3s wait → self-kill …). Trip into 'failed' state after 5
        # restarts within 60s so the pressure surfaces (alert, journal
        # inspect) instead of burning CPU on rapid restart cycles.
        StartLimitBurst = 5;
        StartLimitIntervalSec = 60;
      };
      environment.NOCTALIA_CONFIG_HOME = "/etc";
    };
    environment.systemPackages = [noctalia-patched];

    # ── Write the TOML config to /etc/noctalia/config.toml ──────────────
    environment.etc."noctalia/config.toml".source = noctaliaConfigFile;
  };
}
