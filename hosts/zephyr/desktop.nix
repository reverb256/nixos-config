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
      # HDR fork binary — declarative pkgs.niri-hdr (dividebysandwich/niri
      # hdr-smithay-master, see overlays/system.nix). 2026-08-04 audit (WS1):
      # was an imperative `cargo build && sudo cp /usr/local/bin/niri-hdr`
      # (not in the closure, lost on reinstall). Now a store path. The fork
      # build must be verified before deploy (see PR — cargoLock regenerated).
      binPath = lib.mkForce "${pkgs.niri-hdr}/bin/niri";
    };
  };

  desktop.uwsm-sessions.enable = true;
  programs.niri.enable = true;

  # Samsung TV brightness via Tizen WS API
  desktop.samsung-tv-brightness.enable = true;
  desktop.zephyr-sdr-brightness.enable = true;

  # NVIDIA tuning + Samsung TV HDR config for niri
  desktop.niri-hdr-samsung.enable = true;

  # Noctalia v5 (noctalia flake input) is enabled automatically by
  # modules/desktop/wayland-compositor-common.nix whenever `programs.niri.enable`
  # is true. The binary is launched via the niri `spawn-at-startup` list in
  # modules/home-manager/niri-config.nix (`uwsm app -s s -- noctalia`) which
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
}
