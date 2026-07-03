{pkgs, ...}: {
  # Enable UWSM (Universal Wayland Session Manager) for proper session management.
  # 2026-07-03: binPath points at the raw `niri` binary rather than the
  # nixpkgs-26.04 `niri-session` wrapper, which conflicts with uwsm's
  # wayland-compositor@.service supervision and times out at ~42 s
  # (sddm-helper exit 64, greeter loop). Same fix applied to zephyr
  # in hosts/zephyr/desktop.nix and the shared modules/desktop/niri.nix.
  programs.uwsm = {
    enable = true;
    waylandCompositors.niri = {
      prettyName = "Niri";
      comment = "A scrollable-tiling Wayland compositor";
      binPath = "/run/current-system/sw/bin/niri";
    };
  };

  programs.niri.enable = true;
  desktop.uwsm-sessions.enable = true;

  services.displayManager.defaultSession = "niri-uwsm";
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";

  services.flatpak.enable = true;

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
