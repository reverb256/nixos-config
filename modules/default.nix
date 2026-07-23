# Default module imports for all submodules
# Modules are organized into logical subdirectories for better maintainability
{ ... }:
{
  imports = [
    # ============================================================================
    # SHARED DEFAULTS
    # ============================================================================
    ./common-host-defaults.nix

    # Common shared modules
    ./common/environment-variables.nix
    ./common/firewall-ports.nix

    # Helper libraries (DRY enforcement)

    # Network configuration
    ./network-constants.nix

    # System-level configuration
    ./system/system-packages.nix
    ./system/nix-config.nix
    ./system/users.nix
    ./system/home-manager.nix
    ./system/networking.nix
    ./system/ssh.nix
    ./system/ssh-ca.nix
    ./system/mosh.nix
    ./system/polkit-rules.nix
    ./system/tailscale.nix
    ./system/kernel-hardening.nix
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
    ./system/cilium-sysctl.nix
    ./system/home-permissions-fix.nix
    ./system/boot-emergency-diagnostics.nix
    ./system/mining-inference-coordinator.nix
    ./system/status-auto-update.nix

    # Security
    ./security/pam-vaultwarden.nix
    ./security/caddy-ca.nix
    ./kubernetes-security.nix

    # Hardware modules
    ./hardware/corsair.nix
    ./hardware/gpu-compute.nix
    ./hardware/monitoring.nix
    ./hardware/nvidia-common.nix
    ./hardware/nvidia-wayland.nix
    ./hardware/amdgpu-wayland.nix

    # Desktop environment
    ./desktop/desktop.nix
    ./desktop/wayland-common.nix
    ./desktop/wayland-compositor-common.nix
    ./desktop/flatpak.nix
    ./desktop/plasma6.nix
    ./desktop/hyprland.nix
    ./desktop/uwsm-sessions.nix
    ./desktop/systems-intelligence-plasmoid.nix
    ./desktop/niri.nix

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
    ./development/ai-coding-tools.nix

    # Gaming
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
    ./services/nfs-server.nix
    ./services/nfs-client.nix
    ./services/tplink-switches.nix
    ./services/tplink-cli.nix
    ./services/lm-studio.nix
    ./services/lm-studio-headless.nix
    ./services/llamafile.nix
    ./services/stability-matrix.nix
    ./services/nixos-share.nix
    ./services/spacebot.nix # Systemd/Podman deployment (current)
    ./services/spacebot/default.nix # Container module for Kubernetes (optional)
    ./services/podman-auto-update.nix
    # ./services/caddy.nix (handled by inputs.caddy-ingress.nixosModules.caddy)
    # ./services/caddy-common.nix (handled by inputs.caddy-ingress.nixosModules.caddy-common)
    # caddy-ingress-common.nix removed — was dead code (comments only)
    ./services/nextcloud.nix
    ./services/service-gateway.nix
    ./services/host-dashboard.nix
    ./services/ci-runner.nix
    ./services/garnix.nix
    ./services/auto-update.nix
    ./services/whisper-dictation.nix
    ./services/cloudflared.nix
    ./services/cluster-ca.nix # Internal CA for cluster services
    ./services/unbound-common.nix # Unified Unbound DNS-over-TLS for all hosts
    ./services/syncthing.nix
    ./services/garage.nix # S3-compatible distributed object storage
    ./services/backup-to-garage.nix # Automated backups to Garage S3
    ./services/binary-cache.nix # Nix binary cache server for cluster
    ./services/rclone.nix # Cloud storage sync (70+ providers)
    ./services/n8n.nix
    ./services/vaultwarden.nix
    ./services/self-healing-alerts.nix

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
    ./system/flake-lock-sync.nix
    # Fallback cache for remote hosts (graceful NFS failure)
    ./system/nixos-fallback-cache.nix
    # Profile system
    ./profiles/default.nix
    ./profiles/node-profiles.nix
    # NixOS config sync — force git origin/main on all hosts
    ./services/nixos-sync.nix
    # Hardware modules
    ./hardware/corsair.nix
    ./hardware/gpu-compute.nix

    # Network modules
    ./network/cluster-hosts.nix
    ./networking/cluster-networking.nix
    # Claude Code Router
    ./services/claude-code-router.nix
    # Supply chain security (7-day cooldown on npm/bun/uv packages)
    ./services/supply-chain-cooldowns.nix
    # Container image security scanning
    ./services/container-scanning.nix
    # Auto-apply Kubernetes manifests on boot
    ./services/k8s-manifest-autoapply.nix
  ];
}
