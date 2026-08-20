{
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ../../modules/desktop/zephyr-sdr-brightness.nix
    ../../modules/desktop/samsung-tv-brightness.nix
    ../../modules/desktop/niri-hdr-samsung.nix
    ../../modules/desktop/desktop-session-watchdog.nix
  ];

  services.displayManager.sddm.enable = lib.mkForce true;
  services.displayManager.sddm.wayland.enable = true;

  # Enable UWSM (Universal Wayland Session Manager) - CRITICAL for Niri session integration.
  # 2026-07-03: binPath points at the raw `niri` binary rather than the
  # nixpkgs 26.04 `niri-session` wrapper, which conflicts with uwsm's
  # wayland-compositor@.service session supervision and timed out at ~42 s
  # (sddm-helper exit 64, greeter loop).
  programs.uwsm = {
    enable = true;
    waylandCompositors.niri = {
      prettyName = "Niri";
      comment = "A scrollable-tiling Wayland compositor";
      # binPath comes from the shared modules/desktop/niri.nix
      # (/run/current-system/sw/bin/niri). The old manual HDR fork deploy
      # (/usr/local/bin/niri-hdr, built via /tmp/niri-hdr cargo) is retired —
      # the fork is now a Nix package (pkgs.niri-hdr) selected below, which
      # links sw/bin/niri to the fork binary.
    };
  };

  # HDR compositor: dividebysandwich/niri hdr-smithay-master fork (pkgs.niri-hdr).
  # mkOverride 40 beats the shared niri.nix mkForce (50) that pins sodiboo
  # niri-unstable. Fork-schema HDR settings (hdr { } block, reference-luminance)
  # come from desktop.niri-hdr-samsung below.
  programs.niri.package = lib.mkOverride 40 pkgs.niri-hdr;

  desktop.uwsm-sessions.enable = true;
  programs.niri.enable = true;

  # Samsung TV brightness via Tizen WS API
  desktop.samsung-tv-brightness.enable = true;
  desktop.zephyr-sdr-brightness.enable = true;

  # NVIDIA tuning + Samsung TV HDR config for niri
  desktop.niri-hdr-samsung.enable = true;

  # 2026-08-14: restart the DM automatically if the graphical session dies
  # and sddm wedges (no greeter, no session) instead of leaving the desktop
  # dead until a manual restart.
  desktop.session-watchdog.enable = true;

  # Noctalia v5 (noctalia flake input) is enabled automatically by
  # modules/desktop/wayland-compositor-common.nix whenever `programs.niri.enable`
  # is true. The binary is launched via the niri `spawn-at-startup` list in
  # home-manager-config/modules/niri-config.nix (`uwsm app -s s -- noctalia`) which
  # runs inside the uwsm-managed systemd --user session.
  # `programs.noctalia.systemd.enable` is intentionally left at its upstream
  # default (`false`) to avoid a double-launch against `graphical-session.target`.

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";
  # 2026-07-12: `just switch` re-execs sddm (unit is regenerated), and NixOS's
  # default [Autologin] Relogin=false makes sddm drop to the greeter on ANY
  # restart instead of auto-logging-in j_kro. Force Relogin=true so the
  # niri-uwsm session comes back automatically after every switch, not a greeter.
  services.displayManager.sddm.settings.Autologin.Relogin = true;
  services.displayManager.defaultSession = "niri-uwsm";

  services.flatpak-kde = {
    enable = true;
    autoUpdate = true;
  };

  services.spotify-spotx = {
    enable = true;
    forceX11 = true;
    clearCacheOnPatch = true;
  };

  services.multimedia.gstreamer.enable = true;

  # Steam Remote Play — stream games from zephyr to other devices.
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
  };
}
