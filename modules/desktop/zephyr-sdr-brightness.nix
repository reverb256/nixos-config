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

  # ── Stylix palette → Noctalia v5 (declarative, system-managed) ──────────
  # The noctalia daemon reads its ENTIRE config from /etc/noctalia (set by
  # NOCTALIA_CONFIG_HOME=/etc on the systemd unit below). The home-manager
  # path (~/.config/noctalia) is therefore NEVER consulted by the running
  # daemon — so the Stylix activation must live here in /etc/noctalia, not in
  # the HM leaf module. Generated from config.lib.stylix.colors so it tracks
  # the cluster's per-host base16 scheme automatically.
  #
  # v5 reads CUSTOM palettes from palettes/<name>.json (the v4 colorschemes/
  # path is ignored for custom selection). The [theme] block selects it.
  stylixNoctaliaPalette = let
    raw = config.lib.stylix.colors;
    h = hex: "#" + hex;
    dark = {
      mShadow = h raw.base00;
      mSurface = h raw.base01;
      mSurfaceVariant = h raw.base02;
      mOutline = h raw.base03;
      mOnSurfaceVariant = h raw.base04;
      mOnSurface = h raw.base05;
      mOnPrimary = h raw.base07;
      mOnSecondary = h raw.base07;
      mPrimary = h raw.base0D;
      mSecondary = h raw.base0B;
      mTertiary = h raw.base0A;
      mError = h raw.base08;
      mOnError = h raw.base07;
      mHover = h raw.base09;
      mOnHover = h raw.base07;
      mOnTertiary = h raw.base07;
    };
    light = {
      mShadow = h raw.base07;
      mSurface = h raw.base06;
      mSurfaceVariant = h raw.base05;
      mOutline = h raw.base04;
      mOnSurfaceVariant = h raw.base02;
      mOnSurface = h raw.base01;
      mOnPrimary = h raw.base00;
      mOnSecondary = h raw.base00;
      mPrimary = h raw.base0D;
      mSecondary = h raw.base0B;
      mTertiary = h raw.base0A;
      mError = h raw.base08;
      mOnError = h raw.base00;
      mHover = h raw.base09;
      mOnHover = h raw.base00;
      mOnTertiary = h raw.base00;
    };
    terminal = {
      cursorText = h raw.base00;
      cursor = h raw.base0D;
      foreground = h raw.base05;
      background = h raw.base00;
      selectionFg = h raw.base05;
      selectionBg = h raw.base02;
      normal = {
        black = h raw.base00;
        red = h raw.base08;
        green = h raw.base0B;
        yellow = h raw.base0A;
        blue = h raw.base0D;
        magenta = h raw.base0E;
        cyan = h raw.base0C;
        white = h raw.base05;
      };
      bright = {
        black = h raw.base03;
        red = h raw.base08;
        green = h raw.base0B;
        yellow = h raw.base0A;
        blue = h raw.base0D;
        magenta = h raw.base0E;
        cyan = h raw.base0C;
        white = h raw.base06;
      };
    };
  in builtins.toJSON {
    dark = dark // {terminal = terminal;};
    light = light // {terminal = terminal;};
  };

  # [theme] activation — selects the Stylix custom palette as the active scheme.
  # Loads in /etc/noctalia (the daemon's resolved config dir), alphabetically
  # after config.toml, so it is the base-layer default. Any GUI state override
  # in ~/.local/state/noctalia/settings.toml still wins if present (clear it
  # once after deploy: see PROCEDURE notes).
  stylixNoctaliaTheme = pkgs.writeText "noctalia-theme-stylix.toml" ''
    # ── Stylix palette activation (generated by nixos-config) ──
    [theme]
    mode = "dark"
    source = "custom"
    custom_palette = "Stylix"
    wallpaper_scheme = "m3-tonal-spot"
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
        # Broadened 2026-08-17 (issue #661): Noctalia launches desktop apps
        # via `systemd-run` (launch_apps_as_systemd_services = true). The
        # pinned PATH stripped ~/.nix-profile/bin and ~/.local/bin, so
        # systemd-run could not resolve user-profile launchers
        # (freebuff-desktop-latest, vesktop, hermes). Keep /run/current-system/sw/bin
        # first (ddcutil + niri backend discovery), then the user profile dirs.
        Environment = "PATH=/run/current-system/sw/bin:/home/j_kro/.nix-profile/bin:/home/j_kro/.local/bin:/home/j_kro/bin";
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

    # ── Write the Stylix palette + [theme] activation to /etc/noctalia ──
    # The daemon reads config from here (NOCTALIA_CONFIG_HOME=/etc), so this
    # is what actually activates Stylix. palettes/Stylix.json is the v5
    # custom-palette location; theme-stylix.toml selects it.
    environment.etc."noctalia/palettes/Stylix.json".text = stylixNoctaliaPalette;
    environment.etc."noctalia/theme-stylix.toml".source = stylixNoctaliaTheme;
  };
}
