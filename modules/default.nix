# Default module imports for all submodules
{...}: {
  imports = [
    ./system-packages.nix
    ./users.nix
    ./networking.nix
    ./gaming.nix
    ./mining.nix
    ./mining-plasmoid.nix # Plasma plasmoid for mining monitoring
    ./ssh.nix
    ./systemd-slices.nix
    ./flatpak-polkit.nix
    ./nix-config.nix # Binary caches and Nix settings
    ./minio-cache.nix # S3 binary cache client support
    ./vm-tuning.nix # VM overcommit fixes for Discover crashes
    ./peripherals.nix # Razer and Corsair peripheral support
    ./keyboard-shortcuts.nix # Keyboard shortcuts configuration
    ./scopebuddy.nix # ScopeBuddy gamescope wrapper
    ./security-hardware.nix # YubiKey and Bitwarden CLI
    ./opencode.nix # OpenCode/oh-my-opencode configuration
  ];
}
