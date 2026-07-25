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
  noctalia-patched = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
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
      };
      environment.NOCTALIA_CONFIG_HOME = "/etc";
    };
    environment.systemPackages = [noctalia-patched];

    # ── Write the TOML config to /etc/noctalia/config.toml ──────────────
    environment.etc."noctalia/config.toml".source = noctaliaConfigFile;
  };
}
