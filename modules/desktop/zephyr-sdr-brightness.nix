{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  inherit (lib) mkIf mkForce mkOverride mkOption types;
  cfg = config.desktop.zephyr-sdr-brightness;

  # ── Patched niri with sdr-brightness IPC command ──────────────────────
  # Adds NV_PLANE_DEGAMMA_MULTIPLIER support via the
  # `niri msg output <name> sdr-brightness <0..1>` IPC verb.
  niri-patched = pkgs.niri.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./../../patches/niri-sdr-brightness.patch];
  });

  # ── Patched noctalia daemon with SDR brightness backend ──────────────
  # Adds the `Sdr` backend to BrightnessService::setBrightness(). When the
  # TOML config maps HDMI-A-2 to backend="sdr", dragging the brightness
  # slider in the control center calls setSdrBrightness() which shells out
  # to `niri msg output <name> sdr-brightness <value>`.
  noctalia-patched = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./../../patches/noctalia-sdr-brightness.patch];
  });

  # ── TOML config for noctalia brightness ──────────────────────────────
  # Written to /etc/noctalia/config.toml. The NOCTALIA_CONFIG_HOME env var
  # (set in the systemd user service environment below) points noctalia's
  # configDir() at /etc/noctalia/. This gives us declarative control over
  # the brightness backend per-monitor without touching the user's home.
  #   - enableDdcSupport: enables the DDC/CI backend for DP-4/5/6
  #   - backend = "sdr" on HDMI-A-2: marks the Samsung TV as compositor-driven
  #     SDR brightness (requires the noctalia and niri patches above)
  noctaliaConfigFile = pkgs.writeText "noctalia-config.toml" ''
    [brightness]

    [brightness.monitor."HDMI-A-2"]
    backend = "sdr"
  '';
in {
  options.desktop.zephyr-sdr-brightness = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SDR brightness via NV_PLANE_DEGAMMA_MULTIPLIER on zephyr's Samsung TV";
    };
  };

  config = mkIf cfg.enable {
    # ── Patched niri ────────────────────────────────────────────────────
    # niri.nix already sets `programs.niri.package = mkForce pkgs.niri`.
    # We override with an even higher priority (40 < 50) to beat mkForce.
    programs.niri.package = mkOverride 60 niri-patched;

    # ── Patched noctalia daemon ─────────────────────────────────────────
    # wayland-compositor-common.nix sets desktop.noctalia.daemonPackage as
    # a mkOption (priority 100). mkForce beats the default.
    desktop.noctalia.daemonPackage = mkForce noctalia-patched;

    # ── Systemd environment: point noctalia at our TOML config ──────────
    # /etc/noctalia/ contains the system-managed TOML config. Setting
    # NOCTALIA_CONFIG_HOME here overrides the default
    # ~/.config/noctalia/ search path for the noctalia daemon process.
    systemd.user.services.noctalia.environment = {
      NOCTALIA_CONFIG_HOME = "/etc";
    };

    # ── Write the TOML config to /etc/noctalia/config.toml ──────────────
    environment.etc."noctalia/config.toml".source = noctaliaConfigFile;
  };
}
