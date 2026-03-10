# Default module imports for all submodules
# Modules are organized into logical subdirectories for better maintainability
{...}: {
  imports = [
    # ============================================================================
    # SHARED DEFAULTS
    # ============================================================================
    ./common-host-defaults.nix

    # Network configuration
    ./network-constants.nix

    # System-level configuration
    ./system/nix-config.nix
    ./system/users.nix
    ./system/home-manager.nix
    ./system/ssh.nix
    ./system/ssh-ca.nix
    ./system/mosh.nix
    ./system/polkit-rules.nix
    ./system/tailscale.nix
    ./system/kernel-hardening.nix
    ./system/fetch-tools.nix
    ./system/boot-error-fixes.nix
    ./system/agenix-fixes.nix
    ./system/cluster-storage.nix
    ./system/security-hardening.nix
    ./system/btrfs-compression.nix

    # Security
    ./security/pam-vaultwarden.nix

    # Desktop environment
    ./desktop/desktop.nix
    ./desktop/wayland-common.nix
    ./desktop/flatpak.nix
    ./desktop/hyprland.nix
    ./desktop/systems-intelligence-plasmoid.nix

    # Shell configuration
    # Fish system-level (PATH, packages): ./shell/fish.nix
    # Fish user-level (aliases, prompt): Home Manager (./system/home-manager.nix)
    ./shell/bash.nix
    ./shell/fish.nix

    # Development
    ./development/tools.nix
    ./development/lsp.nix
    ./development/programming-languages.nix
    ./development/opencode.nix
    ./development/web-testing.nix

    # Gaming
    ./gaming/gaming.nix
    ./gaming/gaming-hdr.nix
    ./gaming/scopebuddy.nix

    # Mining
    ./mining/mining.nix
    ./mining/mining-build-wrapper.nix

    # Services
    ./services/mcp-servers.nix
    ./services/tplink-switches.nix
    ./services/tplink-cli.nix
    ./services/lm-studio.nix
    ./services/lm-studio-headless.nix
    ./services/stability-matrix.nix
    ./services/ai-inference/default.nix
    ./services/nixos-share.nix
    ./services/spacebot.nix
    ./services/podman-auto-update.nix
    ./services/glitchtip-selfhosted.nix
    ./services/caddy.nix
    ./services/nextcloud.nix
    ./services/service-gateway.nix
    ./services/ci-runner.nix
    ./services/garnix.nix
    ./services/auto-update.nix
    ./services/whisper-dictation.nix
    ./services/unbound-cluster.nix
    ./services/searxng.nix
    ./services/n8n.nix
    ./services/vaultwarden.nix

    # Monitoring
    # ./services/monitoring/default.nix  # TEMP: Compatibility issues with latest NixOS
    # ./services/monitoring/prometheus.nix
    # ./services/monitoring/grafana.nix
    # ./services/monitoring/node-exporter.nix

    # Exporters
    ./services/gpu-exporters.nix
    ./services/mining-exporter.nix

    # Hardware modules
    ./hardware/nvidia-common.nix
    ./hardware/monitoring.nix
    ./hardware/corsair.nix

    # Multimedia modules
    ./multimedia/gstreamer.nix

    # Desktop modules (Spotify customization)
    ./desktop/spotify-spotx.nix

    # Distributed builds
    ./system/distributed-builds.nix

    # Profile system
    ./profiles/default.nix

    # Network modules
    ./network/cluster-hosts.nix
  ];
}
