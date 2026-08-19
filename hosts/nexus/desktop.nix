{
  pkgs,
  lib,
  ...
}: {
  # Enable UWSM (Universal Wayland Session Manager) for proper session management.
  # Even though Nexus is headless, UWSM provides the necessary infrastructure.
  # 2026-07-03: binPath points at the raw `niri` binary rather than the
  # nixpkgs-26.04 `niri-session` wrapper. The niri + uwsm-sessions pair is
  # mkForce-false below, so this value is dead config today, but it would
  # become load-bearing if either toggle flipped back to true. Keeping it in
  # sync with zephyr/forge/sentry avoids surprise reactivation. Same fix
  # shape as commits db97c0c0 + the shared module in modules/desktop/niri.nix.
  programs.uwsm = {
    enable = true;
    waylandCompositors.niri = {
      prettyName = "Niri";
      comment = "A scrollable-tiling Wayland compositor";
      binPath = "/run/current-system/sw/bin/niri";
    };
  };

  programs.niri.enable = true;
  desktop.uwsm-sessions.enable = lib.mkForce false;

  # Noctalia v5 shell — install the binary but DO NOT enable the systemd
  # user service (`graphical-session.target` upstream). Nexus is headless
  # with no Wayland compositor and no planned cage/kiosk unit; enabling the
  # systemd service would crash-loop the moment any future user session
  # reached `graphical-session.target`. Package wiring happens in
  # modules/desktop/wayland-compositor-common.nix.
  programs.noctalia.enable = true;

  # SteamOS-style gamescope session on the 4K TV. Nexus IS attached to a
  # display (HDMI-A-1 4K TV), so the headless DM disable is retired (it was
  # a holdover from the GPU-handoff VM era, which is now dropped — gaming VM
  # lives on zephyr only). NixOS 26.11 auto-migrates
  # `services.displayManager.autoLogin.*` into the legacy lightdm namespace
  # whenever xserver is enabled, so we use the SDDM-native path exactly like
  # zephyr (sddm.enable mkForce true + sddm.wayland.enable + autologin in the
  # new namespace). Dual sessions: Steam (gamescope) is the console default;
  # niri-uwsm remains available as the desktop session.
  services.xserver.enable = lib.mkForce true;
  services.displayManager.enable = lib.mkForce true;
  services.displayManager.sddm.enable = lib.mkForce true;
  services.displayManager.sddm.wayland.enable = true;
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";
  services.displayManager.defaultSession = lib.mkForce "steam";
  services.displayManager.sddm.settings.Autologin.Relogin = true;

  # Nexus runs Steam inside the native Gamescope session. Do not grant
  # CAP_SYS_NICE here: the inherited capability makes Steam's non-setuid
  # Bubblewrap sandbox abort with "Unexpected capabilities but not setuid".
  # Zephyr retains the global capability setting for its separate HDR path.
  programs.gamescope.capSysNice = lib.mkForce false;

  # Sole owner of the native Steam Gamescope session for Nexus. Keep the
  # session declaration beside SDDM/autologin rather than duplicating it in
  # cluster-service or shared gaming modules.
  programs.steam = {
    enable = true;
    # Native Steam Remote Play (in-home streaming). Uses NVENC on the RTX 3060
    # Ti. Opens the Remote Play ports in the firewall.
    remotePlay.openFirewall = true;
    gamescopeSession = {
      enable = lib.mkForce true;
      args = [
        "--expose-wayland"
        "--force-composition"
        "-W"
        "3840"
        "-H"
        "2160"
        "-r"
        "60"
      ];
    };
  };

  # Sunshine game-stream host (Moonlight client on zephyr). Installed at the
  # NixOS layer because it needs cap_sys_admin (Wayland KMS capture), the uinput
  # module, udev rules, and firewall — none of which Home Manager owns.
  # Run via the systemd --user unit (autoStart) under the gamescope session.
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true; # Wayland KMS capture on non-wlroots compositor
    openFirewall = true;
    package = pkgs.sunshine.override { cudaSupport = true; };
  };

  # Sunshine emulates input devices through /dev/uinput; j_kro must be in the
  # uinput group. The module loads the uinput module + ships udev rules, but the
  # group membership is ours to declare.
  users.users.j_kro.extraGroups = [ "uinput" ];

  services.flatpak.enable = true;
  xdg.portal.enable = true;
  xdg.portal.config.common.default = "*";
  xdg.portal.extraPortals = with pkgs; [xdg-desktop-portal-gtk xdg-desktop-portal-gnome];

  system.activationScripts.flatpak-setup = ''
    echo "Setting up Flatpak remotes..."
    ${pkgs.flatpak}/bin/flatpak remote-list --system | grep -q flathub || \
      ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo
  '';

  environment.etc."polkit-1/rules.d/org.flathub.flatpak.rules".text = ''
    polkit.addRule(function(action, subject) {
      if ((action.id == "org.freedesktop.flatpak.system-helper" ||
           action.id == "org.freedesktop.flatpak.auth-helper") &&
           subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';
}
