{pkgs, ...}: {
  programs.niri.enable = lib.mkForce false;  # Headless — no display
  programs.noctalia.enable = true;  # v5 — runs as Wayland shell via niri spawn

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
