# Common Host Module - Shared imports for cluster nodes that use desktop/gaming
# This module is imported by hosts with desktop environments (zephyr, nexus, forge, sentry)
# Note: modules/ directory is already imported globally via common-base.nix
#
# Host-specific modules still imported separately in host configs:
#   - nvidia-wayland.nix (zephyr, nexus, forge)
#   - amdgpu-wayland.nix (sentry)
#   - stability-matrix.nix (zephyr only)
#   - nix-cache-server.nix (zephyr only)
#   - aistor-secrets.nix (zephyr, nexus)
#   - mcp-servers.nix (zephyr, nexus)
#
# Gaming: Enabled with services.gaming.enable = true
# VR: Enabled with services.gaming.vr.enable = true (only zephyr/nexus)
{...}: {
  imports = [
    # Shared defaults (stateVersion, logind, displayManager)
    ./common-host-defaults.nix

    # Desktop environment (Plasma 6 + Wayland)
    # NOTE: Not in default.nix since some hosts might be headless
    ./desktop.nix

    # Shell configuration
    ./fish-starship.nix

    # Tailscale VPN mesh
    # NOTE: Not in default.nix since some hosts might not need it
    ./tailscale.nix

    # CI/CD integration
    ./garnix.nix

    # Auto-update configuration
    ./auto-update.nix

    # Distributed builds across cluster
    # NOTE: Not in default.nix since configuration varies by host
    ./distributed-builds.nix

    # Mining-aware build wrapper
    # NOTE: Not in default.nix since only some hosts mine
    ./mining-build-wrapper.nix
  ];
}
