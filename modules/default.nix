# Default module imports for all submodules
# Modules are organized into logical subdirectories for better maintainability
{ ... }:
{
  imports = [
    # Network configuration
    ./network-constants.nix
    # ./network/wifi.nix  # TODO: Fix module before enabling
    # ./network/bluetooth.nix  # TODO: Fix module before enabling

    # System-level configuration
    ./system/nix-config.nix
    ./system/users.nix

    # Desktop environment
    ./desktop/plasma6.nix
    ./desktop/wayland-common.nix
    ./desktop/flatpak.nix

    # Shell configuration
    ./shell/fish.nix
    ./shell/starship.nix

    # Gaming
    ./gaming/gaming.nix
    ./gaming/gaming-hdr.nix
    ./gaming/scopebuddy.nix

    # Mining
    ./mining/mining.nix
    #./mining/mining-plasmoid.nix  # TODO: Requires plasmoids/mining-monitor which doesn't exist

    # Development
    ./development/tools.nix
    ./development/lsp.nix
    ./development/programming-languages.nix

    # Services
    ./services/lm-studio.nix
    ./services/lm-studio-headless.nix
    ./services/stability-matrix.nix
    ./services/ai-inference/default.nix

    # Monitoring
    ./services/monitoring/default.nix
    ./services/monitoring/prometheus.nix
    ./services/monitoring/grafana.nix
    ./services/monitoring/node-exporter.nix

    # Exporters
    ./services/gpu-exporters.nix
    ./services/mining-exporter.nix
  ];
}
