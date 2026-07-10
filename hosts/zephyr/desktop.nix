{
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ../../modules/desktop/zephyr-sdr-brightness.nix
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
      binPath = "/run/current-system/sw/bin/niri";
    };
  };

  desktop.uwsm-sessions.enable = true;
  programs.niri.enable = true;

  # Noctalia v5 (noctalia flake input) is enabled automatically by
  # modules/desktop/wayland-compositor-common.nix whenever `programs.niri.enable`
  # is true. The binary is launched via the niri `spawn-at-startup` list in
  # modules/home-manager/niri-config.nix (`uwsm app -s s -- noctalia`) which
  # runs inside the uwsm-managed systemd --user session.
  # `programs.noctalia.systemd.enable` is intentionally left at its upstream
  # default (`false`) to avoid a double-launch against `graphical-session.target`.

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";
  services.displayManager.defaultSession = "niri-uwsm";

  services.gaming.hdr.enable = true;
  services.gaming.vr.enable = true;

  programs.gamescope.enable = true;  # Required by gamescopeSession

  services.gaming.gamescopeSession = {
    enable = true;
    vkDeviceFilter = "10de:2204"; # RTX 3090 — prevents Vulkan from touching the 3060 Ti
  };

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
