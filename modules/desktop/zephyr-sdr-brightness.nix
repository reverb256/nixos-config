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
  # HDMI-A-1 (Samsung TV) now runs HDR natively under niri-unstable, so its
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
  #   - enableDdcSupport: enables the DDC/CI backend for DP-1/2/3
  #   - backend = "normal" on HDMI-A-1: the Samsung TV is HDR-driven natively
  #     by niri-unstable (max_bpc / HDR); niri owns the output. The custom
  #     niri SDR-brightness patch was dropped 2026-07-25.
  noctaliaConfigFile = pkgs.writeText "noctalia-config.toml" ''
    [brightness]
    enable_ddcutil = true

    [brightness.monitor."HDMI-A-1"]
    backend = "normal"

    # Launch Electron apps (Vesktop, Discord, Hermes Desktop, etc.) as transient
    # systemd --user units instead of direct spawn. Direct spawn of Electron under
    # Noctalia v5 dies silently (terminal launch works, launcher does nothing) —
    # upstream issue #2519. Requires Noctalia itself to run as a systemd user
    # service, which it does here. ENABLE 2026-08-11 for Hermes Desktop launcher.
    [shell]
    launch_apps_as_systemd_services = true
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
        OOMScoreAdjust = -1000;
        # 2026-08-03 (Cyberpunk OOM kill): oomd SwapUsedLimit=90 killed this
        # unit at 02:24 while the game ran (zram hit 100%). Exempt the gaming
        # session slice from oomd's cgroup kill entirely — earlyoom's --avoid
        # (now including steam/GameThread/REDprelauncher) remains the defense
        # for memory pressure. Kernel OOM would still apply as last resort.
        ManagedOOMSwap = "off";
        # 2026-08-06: systemd-oomd killed 346 procs in this unit's cgroup at
# 18:25:33 (slice-wide memory pressure: 4 peakminers + llama-server +
# PoE2). `OOMScoreAdjust` alone was insufficient because oomd kills by
# cgroup under global slice pressure, not by per-process score.
# ManagedOOMPreference=avoid sets the user.oomd_avoid xattr so oomd
# deprioritizes this cgroup as a kill candidate (only selected if no
# other viable candidate exists). NOTE: ManagedOOMMemoryPressure=avoid
# is INVALID (that key only takes auto|kill); the avoid/omit preference is
# the correct knob.
        ManagedOOMPreference = "avoid";
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
