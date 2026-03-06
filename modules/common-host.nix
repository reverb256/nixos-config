# Common Host Module - Shared imports for cluster nodes that use desktop/gaming
# This module is imported by hosts with desktop environments (zephyr, nexus, forge, sentry)
# Note: modules/ directory is already imported globally via common-base.nix
#
# Host-specific modules still imported separately in host configs:
#   - hardware/nvidia-wayland.nix (zephyr, nexus, forge)
#   - hardware/amdgpu-wayland.nix (sentry)
#   - services/stability-matrix.nix (zephyr only)
#   - system/nix-cache-server.nix (zephyr only)
#   - security/aistor-secrets.nix (zephyr, nexus)
#   - services/mcp-servers.nix (zephyr, nexus)
#
# Gaming: Enabled with services.gaming.enable = true
# VR: Enabled with services.gaming.vr.enable = true (only zephyr/nexus)
{...}: {
  imports = [
    # Shared defaults (stateVersion, logind, displayManager)
    ./common-host-defaults.nix

    # Desktop environment (Plasma 6 + Wayland)
    # NOTE: Not in default.nix since some hosts might be headless
    ./desktop/desktop.nix

    # Shell configuration
    ./development/fish-starship.nix

    # Tailscale VPN mesh
    # NOTE: Not in default.nix since some hosts might not need it
    ./system/tailscale.nix

    # CI/CD integration
    ./services/garnix.nix

    # Auto-update configuration
    ./services/auto-update.nix

    # Distributed builds across cluster
    # NOTE: Not in default.nix since configuration varies by host
    ./system/distributed-builds.nix

    # Mining-aware build wrapper
    # NOTE: Not in default.nix since only some hosts mine
    ./mining/mining-build-wrapper.nix

    # Speech-to-text dictation (desktop environments)
    # NOTE: Not in default.nix since only desktop hosts need audio/keyboard injection
    ./services/whisper-dictation.nix
  ];
}
