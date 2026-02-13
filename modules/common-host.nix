# Common Host Module - Shared imports for all cluster nodes
# This eliminates duplication across hosts/*/configuration.nix
#
# Usage: Import this module in host configs, then add host-specific modules
#
# Host-specific modules still imported separately:
#   - nvidia-wayland.nix (zephyr, nexus, forge)
#   - amdgpu-wayland.nix (sentry)
#   - stability-matrix.nix (zephyr only)
#   - nix-cache-server.nix (zephyr only)
#   - aistor-secrets.nix (zephyr, nexus)
#   - mcp-servers.nix (zephyr, nexus)
#
# Gaming: Enabled with services.gaming.enable = true
# VR: Enabled with services.gaming.vr.enable = true (only zephyr/nexus)
{ ... }: {
  imports = [
    # Desktop environment (Plasma 6 + Wayland)
    ./desktop.nix

    # Shell configuration
    ./fish-starship.nix

    # Gaming support (optional - enable per-host)
    # services.gaming.enable = true
    # services.gaming.vr.enable = true (only for zephyr/nexus)
    ./gaming.nix

    # Network configuration (DNS, firewall, Avahi)
    ./networking.nix

    # Tailscale VPN mesh
    ./tailscale.nix

    # CI/CD integration
    ./garnix.nix

    # Auto-update configuration
    ./auto-update.nix

    # SSH hardening
    ./ssh.nix

    # Mining services (conditional per-host)
    ./mining.nix

    # Distributed builds across cluster
    ./distributed-builds.nix

    # BTRFS storage management
    ./storage-btrfs.nix

    # Mining-aware build wrapper
    ./mining-build-wrapper.nix
  ];
}
