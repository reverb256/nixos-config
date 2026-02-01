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
    # ./openclaw.nix  # DISABLED: nix-openclaw flake severely broken (hash mismatches, missing files, API changes)
    ./flatpak-polkit.nix
  ];
}
