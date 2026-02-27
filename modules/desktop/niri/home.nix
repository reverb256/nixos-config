# Niri Home Manager Configuration
# Scrollable tiling Wayland compositor user configuration
{pkgs, ...}: {
  imports = [
    ./settings.nix
    ./binds.nix
  ];

  # Enable Niri (when package becomes available)
  # programs.niri = {
  #   enable = true;
  # };

  # Home Manager packages for Niri
  home.packages = with pkgs; [
    waybar
    rofi
    mako
    swaylock-effects
    wlogout
    grim
    slurp
    wl-clipboard
    wf-recorder
    hyprpicker
  ];
}
