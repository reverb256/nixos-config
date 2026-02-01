# Default module imports for all submodules
{...}: {
  imports = [
    ./environment.nix
    ./system-packages.nix
    ./users.nix
    ./networking.nix
    ./gaming.nix
    ./mining.nix
    ./ssh.nix
    ./systemd-slices.nix
    ./flatpak-polkit.nix
  ];
}
