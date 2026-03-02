# Default module imports for all submodules
# Modules are organized into logical subdirectories for better maintainability
{...}: {
  imports = [
    # System-level configuration
    ./system/nix-config.nix
    ./system/users.nix

    # Desktop environment
    ./desktop/plasma6.nix
    ./desktop/wayland-common.nix

    # Shell configuration
    ./shell/fish.nix
    ./shell/starship.nix

    # Gaming
    ./gaming/gaming.nix
    ./gaming/gaming-hdr.nix
    ./gaming/scopebuddy.nix

    # Development
    ./development/tools.nix
    ./development/lsp.nix
    ./development/programming-languages.nix

    # Services
    ./services/lm-studio.nix
    ./services/stability-matrix.nix
  ];
}
