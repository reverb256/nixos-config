# Default module imports for all submodules
# Modules are organized into logical subdirectories for better maintainability
{...}: {
  imports = [
    # System-level configuration
    ./system/system-packages.nix
    ./system/users.nix
    ./system/networking.nix
    ./system/ssh.nix
    ./system/systemd-slices.nix
    ./system/nix-config.nix # Binary caches and Nix settings
    ./system/vm-tuning.nix # VM overcommit fixes for Discover crashes
    ./system/storage.nix
    ./system/storage-btrfs.nix

    # Desktop environment
    ./hardware/rgb.nix # RGB lighting control (Corsair, Razer, Gigabyte/Aorus, MSI, EVGA)
    ./desktop/stylix-rgb-sync.nix # Sync Stylix colors to OpenRGB hardware
    ./desktop/synapse-theme.nix # Synapse theme generation from Stylix colors
    ./desktop/keyboard-shortcuts.nix # Keyboard shortcuts configuration
    ./desktop/hyprland.nix # Hyprland window manager

    # Gaming
    ./gaming/gaming.nix
    ./gaming/scopebuddy.nix # ScopeBuddy gamescope wrapper

    # Mining
    ./mining/mining.nix
    ./mining/mining-plasmoid.nix # Plasma plasmoid for mining monitoring

    # Services
    ./services/flatpak-polkit.nix
    ./services/minio-cache.nix # S3 binary cache client support
    # ./services/hyperwhisper.nix # HyperWhisper desktop speech-to-text app (disabled - flake reference issue)
    ./services/nanoclaw.nix # NanoClaw personal AI assistant (optional)

    # Development
    ./development/opencode.nix # OpenCode/oh-my-opencode configuration

    # Security
    ./security/security-hardware.nix # YubiKey and Bitwarden CLI
  ];
}
