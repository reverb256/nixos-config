{pkgs, lib, inputs, ...}: {
  programs.niri.enable = lib.mkForce false;
  desktop.uwsm-sessions.enable = lib.mkForce false;

  # Noctalia v5 — install binary directly (nixosModule has no programs.noctalia option)
  # Binary path: inputs.noctalia.packages.x86_64-linux.default
  environment.systemPackages =
    if inputs ? noctalia
    then [inputs.noctalia.packages.x86_64-linux.default]
    else [];

  # Launch noctalia as a user systemd service (no niri/s compositor needed)
  systemd.user.services.noctalia = lib.mkIf (inputs ? noctalia) {
    Unit = {
      Description = "Noctalia v5 Wayland panel";
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${lib.getExe (inputs.noctalia.packages.x86_64-linux.default)}";
      Restart = "always";
      RestartSec = 5;
    };
    Install = { WantedBy = ["graphical-session.target"]; };
  };

  # Headless — disable all display managers and auto-login
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