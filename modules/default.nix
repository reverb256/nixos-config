# Default module imports for all submodules
{...}: {
  imports = [
    ./system-packages.nix
    ./users.nix
    ./networking.nix
    ./gaming.nix
    ./mining.nix
    ./ssh.nix
    ./systemd-slices.nix
    ./flatpak-polkit.nix
    ./nix-config.nix # Binary caches and Nix settings
    ./minio-cache.nix # S3 binary cache client support
    ./openclaw-storage.nix # OpenClaw storage management
    ./openclaw-backups.nix # OpenClaw automated backups
    ./vm-tuning.nix # VM overcommit fixes for Discover crashes
    ./peripherals.nix # Razer and Corsair peripheral support
    ./keyboard-shortcuts.nix # Keyboard shortcuts configuration
    ./scopebuddy.nix # ScopeBuddy gamescope wrapper
    ./security-hardware.nix # YubiKey and Bitwarden CLI
    ./openclaw-node-host.nix # OpenClaw node host (secure SSH tunnel to gateway)
  ];
}
