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

    # Cluster-wide overlays are applied via modules/system/nix-config.nix
    # (which has the lix overlay). Standalone overlays via imports don't
    # propagate to python3.pkgs (lix's lookup path), so we don't add them here.
    # The aiohttp test override lives in nix-config.nix.

    # Helper libraries (DRY enforcement)

    # Network configuration
    ./network-constants.nix

    # System-level configuration
    ./system/system-packages.nix
    ./system/nix-config.nix
    ./system/users.nix
    ./system/networking.nix
    ./system/ssh.nix
    ./system/ssh-ca.nix
    ./system/mosh.nix
    ./system/polkit-rules.nix
    ./system/tailscale.nix
    ./system/kernel-hardening.nix
    ./system/secretspec-validator.nix
    ./system/vm-tuning.nix
    ./system/fetch-tools.nix
    ./system/boot-error-fixes.nix
    # ./system/agenix-fixes.nix              # Migrated to sops-nix; agenix module no longer loaded
    # ./system/agenix-secrets-registry.nix     # Migrated to sops-nix; agenix module no longer loaded
    ./system/cluster-storage.nix
    ./system/security-hardening.nix
    ./system/cluster-firewall.nix
    ./system/btrfs-compression.nix
    ./system/pi-models.nix
    ./system/btrfs-tuning.nix
    # Modular workload monitoring (replaced old compute-workload-monitor monolith)
    ./system/gaming-detection.nix
    ./system/gpu-profile-manager.nix
    ./system/mining-coordinator.nix
    ./system/oom-protection.nix
    ./system/home-permissions-fix.nix
    ./system/boot-emergency-diagnostics.nix
    ./system/mining-inference-coordinator.nix
    ./system/status-auto-update.nix

    # Security
    ./security/caddy-ca.nix
    ./kubernetes-security.nix
    ./system/sops-secrets-registry.nix

    # Hardware modules
    ./hardware/corsair.nix
    ./hardware/gpu-compute.nix
    ./hardware/monitoring.nix
    ./hardware/nvidia-common.nix
    ./hardware/nvidia-wayland.nix
    ./hardware/amdgpu-wayland.nix
    ./hardware/nvidia-niri-profile.nix

    # Desktop environment
    ./desktop/desktop.nix
    ./desktop/wayland-common.nix
    ./desktop/wayland-compositor-common.nix
    ./desktop/flatpak.nix
    # Niri-only graphical services: monitor layout, TV daemon, and GPU readiness.
    ./desktop/desktop-monitor.nix
    # ./desktop/plasma6.nix — removed: KDE Plasma is not used.
    # ./desktop/hyprland.nix — removed: Hyprland is not used.
    ./desktop/uwsm-sessions.nix
    ./desktop/niri.nix
    ./desktop/alacritty-system.nix

    # Shell configuration
    # Fish system-level (PATH, packages): ./shell/fish.nix
    ./shell/bash.nix
    ./shell/fish.nix

    # Development
    ./development/tools.nix
    ./development/programming-languages.nix
    ./development/opencode.nix
    ./development/web-testing.nix
    ./development/ai-coding-tools.nix

    # Gaming
    ./gaming/dualsense.nix
    ./gaming/gaming.nix
    ./gaming/gaming-hdr.nix
    ./gaming/scopebuddy.nix

    # Mining
    # Most mining modules REMOVED (compute-market, lolminer, xmrig)
    ./mining/mining.nix
    # Note: Python gpu-proxy removed - replaced by gpu-proxy-cpp (centralized on Forge)
    # gpu-proxy handled by inputs.gpu-proxy.nixosModules.default
    # ./mining/gpu-proxy-cpp.nix

    # GPU Resource Marketplace
    # (compute-market removed)
    # ./compute-market/default.nix

    # Services
    # mcp-servers provided by inputs.mcp-registry.nixosModules.default
    # ./services/mcp-servers.nix
    ./services/tplink-switches.nix
    ./services/tplink-cli.nix
    ./services/lm-studio.nix
    ./services/lm-studio-headless.nix
    ./services/llamafile.nix
    ./services/stability-matrix.nix
    ./services/podman-auto-update.nix
    # ./services/caddy.nix (handled by inputs.caddy-ingress.nixosModules.caddy)
    # ./services/caddy-common.nix (handled by inputs.caddy-ingress.nixosModules.caddy-common)
    # caddy-ingress-common.nix removed — was dead code (comments only)
    ./services/nextcloud.nix
    ./services/service-gateway.nix
    ./services/host-dashboard.nix
    ./services/ci-runner.nix
    ./services/auto-update.nix
    ./services/hermes/default.nix
    ./services/hermes-cli.nix
    ./services/whisper-dictation.nix
    ./services/cloudflared.nix
    ./services/cluster-ca.nix # Internal CA for cluster services
    ./services/unbound-common.nix # Unified Unbound DNS-over-TLS for all hosts
    ./services/garage.nix # S3-compatible distributed object storage
    ./services/backup-to-garage.nix # Automated backups to Garage S3
    ./services/binary-cache.nix # Nix binary cache server for cluster
    ./services/rclone.nix # Cloud storage sync (70+ providers)
    ./services/n8n.nix
    ./services/self-healing-alerts.nix
    ./services/memlawb-server.nix  # opt-in encrypted memory server (Hermes MCP backend)

    # Monitoring
    ./services/monitoring/default.nix
    ./services/monitoring/node-exporter.nix
    # Crash detection and diagnostics
    # Exporters
    ./services/gpu-exporters.nix
    # ./services/mining-exporter.nix (removed with compute-market)
    ./services/gputemps-exporter.nix
    # Multimedia modules
    ./multimedia/gstreamer.nix
    # Desktop modules (Spotify customization)
    ./desktop/spotify-spotx.nix
    # Distributed builds
    ./system/distributed-builds.nix
    # Flake lock sync (auto-enabled on remote hosts only)
    # Profile system
    ./profiles/default.nix
    ./profiles/node-profiles.nix
    # NixOS config sync — force git origin/main on all hosts
    ./services/nixos-sync.nix
    # Network modules
    ./network/cluster-hosts.nix
    ./networking/cluster-networking.nix
    # Claude Code Router
    # Supply chain security (7-day cooldown on npm/bun/uv packages)
    ./services/supply-chain-cooldowns.nix
    # Container image security scanning
    ./services/container-scanning.nix
    # Auto-apply Kubernetes manifests on boot
    ./services/k8s-manifest-autoapply.nix
    ./services/fake-backlight-bridge.nix
  ];
}
