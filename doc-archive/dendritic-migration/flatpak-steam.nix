# Flatpak Steam - Controller Support
# Both native and Flatpak Steam installed for maximum compatibility
{
  lib,
  pkgs,
  ...
}:
with lib; {
  # Enable Flatpak
  services.flatpak = {
    enable = true;
  };

  # Install steam-devices udev rules for controller support
  environment.systemPackages = with pkgs; [
    steam-devices-udev-rules
  ];

  # Allow uinput access for virtual gamepad (Steam Input)
  services.udev.extraRules = ''
    # Allow all users access to uinput for Steam Input virtual controllers
    KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
  '';

  # Ensure input group exists
  users.groups.input = {};

  # Optional: Symlink for system tray icons
  systemd.user.services.flatpak-steam-tray = {
    description = "Flatpak Steam tray icon symlink";
    wantedBy = ["graphical-session.target"];
    after = ["graphical-session.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'mkdir -p ~/.local/share/Steam && ln -sf ~/.var/app/com.valvesoftware.Steam/.local/share/Steam ~/.local/share/Steam 2>/dev/null || true'";
    };
  };
}
