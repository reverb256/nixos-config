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
    ./nix-config.nix # Binary caches and Nix settings
    ./minio-cache.nix # S3 binary cache client support
    ./openclaw-storage.nix # OpenClaw storage management
    ./openclaw-backups.nix # OpenClaw automated backups
    ./vm-tuning.nix # VM overcommit fixes for Discover crashes
  ];
}
