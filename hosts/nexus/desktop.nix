{pkgs, lib, ...}: {
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

  programs.niri.enable = lib.mkForce false;
  desktop.uwsm-sessions.enable = lib.mkForce false;

  # Noctalia v5 shell — install the binary but DO NOT enable the systemd
  # user service (`graphical-session.target` upstream). Nexus is headless
  # with no Wayland compositor and no planned cage/kiosk unit; enabling the
  # systemd service would crash-loop the moment any future user session
  # reached `graphical-session.target`. Package wiring happens in
  # modules/desktop/wayland-compositor-common.nix.
  programs.noctalia.enable = true;

  # Headless — disable xserver AND all display managers. NixOS 26.11
  # auto-migrates `services.displayManager.autoLogin.*` into the legacy
  # `services.xserver.displayManager.lightdm.autoLogin.*` namespace whenever
  # xserver is enabled. That pulls in `nixos/modules/.../lightdm.nix`,
  # which references `dmcfg.sessionData.desktops` — a default only populated
  # when a DM is active in the new namespace. With the new namespace fully
  # disabled, the default is unset and evaluation crashes. Disabling xserver
  # here is the minimal correct fix: nexus has no display, no input devices,
  # and never needs a DM. The kiosk-style use cases (future cage unit) can
  # re-enable xserver + sddm in their own override.
  services.xserver.enable = lib.mkForce false;
  services.displayManager.enable = lib.mkForce false;
  services.displayManager.autoLogin.enable = lib.mkForce false;
  services.displayManager.sddm.enable = lib.mkForce false;
  services.displayManager.sddm.wayland.enable = lib.mkForce false;

  services.flatpak.enable = true;
  xdg.portal.enable = true;
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
