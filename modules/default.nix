# Default module imports for all submodules
# Modules are organized into logical subdirectories for better maintainability
{...}: {
  imports = [
    # ============================================================================
    # SHARED DEFAULTS
    # ============================================================================
    ./common-host-defaults.nix

    # Common shared modules
    ./common/environment-variables.nix
    ./common/firewall-ports.nix

    # Helper libraries (DRY enforcement)
    # TEMPORARILY DISABLED: Being fixed (2026-03-23)
    # ./lib/systemd-helpers.nix
    # ./lib/firewall-helpers.nix
    # ./lib/option-helpers.nix

    # Network configuration
    ./network-constants.nix

    # System-level configuration
    ./system/system-packages.nix
    ./system/nix-config.nix
    ./system/users.nix
    ./system/home-manager.nix
    ./system/networking.nix
    # ./system/interface-naming.nix  # DISABLED: Using native enp*s* naming (2026-03-12)
    ./system/ssh.nix
    ./system/ssh-ca.nix
    ./system/mosh.nix
    ./system/polkit-rules.nix
    ./system/tailscale.nix
    ./system/kernel-hardening.nix
    ./system/vm-tuning.nix
    ./system/fetch-tools.nix
    ./system/boot-error-fixes.nix
    ./system/agenix-fixes.nix
    ./system/agenix-secrets-registry.nix
    ./system/cluster-storage.nix
    ./system/security-hardening.nix
    ./system/btrfs-compression.nix
    ./system/btrfs-tuning.nix
    ./system/compute-workload-monitor.nix
    ./system/gaming-detection.nix
    ./system/gpu-profile-manager.nix
    ./system/mining-coordinator.nix
    ./system/oom-protection.nix
    ./system/compute-workload-monitor-profiles.nix
    ./system/home-permissions-fix.nix
    ./system/xmrig-api-control.nix
    ./system/boot-emergency-diagnostics.nix
    ./system/mining-inference-coordinator.nix
    ./system/status-auto-update.nix

    # Security
    ./security/pam-vaultwarden.nix
    ./kubernetes-security.nix

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
    ./mining/dual-xmrig.nix
    ./mining/xmrig-proxy.nix
    ./mining/mining-proxy.nix
    # Note: Python gpu-proxy removed - replaced by gpu-proxy-cpp (centralized on Forge)
    ./mining/gpu-proxy-cpp.nix

    # GPU Resource Marketplace
    ./compute-market/default.nix

    # Services
    ./services/etcd-cluster.nix
    ./services/mcp-servers.nix
    ./services/nfs-server.nix
    ./services/nfs-client.nix
    ./services/tplink-switches.nix
    ./services/tplink-cli.nix
    ./services/lm-studio.nix
    ./services/lm-studio-headless.nix
    ./services/llamafile.nix
    ./services/stability-matrix.nix
    ./services/ai-inference/default.nix
    # ./services/qwen3-tts-preload.nix  # TEMP: Build failure (qwen-tts package)
    ./services/hermes-agent/default.nix
    ./services/nixos-share.nix
    ./services/spacebot.nix  # Systemd/Podman deployment (current)
    ./services/spacebot/default.nix  # Container module for Kubernetes (optional)
    ./services/podman-auto-update.nix
    ./services/glitchtip-selfhosted.nix
    ./services/caddy.nix
    ./services/caddy-common.nix
    ./services/nextcloud.nix
    ./services/service-gateway.nix
    ./services/host-dashboard.nix
    ./services/ci-runner.nix
    ./services/garnix.nix
    ./services/auto-update.nix
    ./services/whisper-dictation.nix
    ./services/cloudflared.nix # Cloudflare Tunnel for Akash provider ingress
    ./services/akash-cloudflare-integration.nix # DNS, cache, metrics for Akash
    ./services/cluster-ca.nix # Internal CA for cluster services
    ./services/unbound-cluster.nix
    ./services/syncthing.nix
    ./services/garage.nix # S3-compatible distributed object storage
    ./services/backup-to-garage.nix # Automated backups to Garage S3
    ./services/binary-cache.nix # Nix binary cache server for cluster
    ./services/rclone.nix # Cloud storage sync (70+ providers)
    ./services/n8n.nix
    ./services/vaultwarden.nix
    # TEMPORARILY DISABLED: Being fixed (2026-03-23)
    # ./services/health-checks.nix
    ./services/self-healing-alerts.nix

    # Monitoring
    ./services/monitoring/default.nix
    ./services/monitoring/node-exporter.nix

    # Crash detection and diagnostics
    # TEMPORARILY DISABLED: Being fixed (2026-03-23)
    # ./services/crash-watchdog.nix

    # Exporters
    ./services/gpu-exporters.nix
    ./services/mining-exporter.nix

    # Hardware modules
    ./hardware/nvidia-common.nix
    ./hardware/monitoring.nix
    ./hardware/corsair.nix
    ./hardware/gpu-compute.nix

    # Multimedia modules
    ./multimedia/gstreamer.nix

    # Desktop modules (Spotify customization)
    ./desktop/spotify-spotx.nix

    # Distributed builds
    ./system/distributed-builds.nix

    # Flake lock sync (auto-enabled on remote hosts only)
    ./system/flake-lock-sync.nix

    # Fallback cache for remote hosts (graceful NFS failure)
    ./system/nixos-fallback-cache.nix

    # Profile system
    ./profiles/default.nix
    ./profiles/node-profiles.nix

    # Network modules
    ./network/cluster-hosts.nix
    ./networking/cluster-networking.nix
  ];
}
