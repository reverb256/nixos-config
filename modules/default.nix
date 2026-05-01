{...}: {
  imports = [
    ./common-host-defaults.nix

    ./common/environment-variables.nix
    ./common/firewall-ports.nix

    ./network-constants.nix

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
    ./system/zram-tuning.nix
    ./system/fetch-tools.nix
    ./system/boot-error-fixes.nix
    ./system/agenix-fixes.nix
    ./system/agenix-secrets-registry.nix
    ./system/cluster-storage.nix
    ./system/security-hardening.nix
    ./system/cluster-firewall.nix
    ./system/btrfs-compression.nix
    ./system/gaming-detection.nix
    ./system/gpu-profile-manager.nix
    ./system/mining-coordinator.nix
    ./system/oom-protection.nix
    ./system/home-permissions-fix.nix
    ./system/xmrig-api-control.nix
    ./system/boot-emergency-diagnostics.nix
    ./system/mining-inference-coordinator.nix
    ./system/status-auto-update.nix

    ./security/pam-vaultwarden.nix
    ./security/gpg.nix

    ./hardware/corsair.nix
    ./hardware/gpu-compute.nix
    ./hardware/monitoring.nix
    ./hardware/nvidia-common.nix
    ./hardware/nvidia-wayland.nix
    ./hardware/amdgpu-wayland.nix

    ./desktop/desktop.nix
    ./desktop/wayland-common.nix
    ./desktop/wayland-compositor-common.nix
    ./desktop/flatpak.nix
    ./desktop/hyprland.nix
    ./desktop/uwsm-sessions.nix
    ./desktop/niri.nix
    ./desktop/noctalia-sdr-brightness.nix
    ./desktop/stylix.nix

    ./shell/bash.nix
    ./shell/fish.nix

    ./development/tools.nix
    ./development/lsp.nix
    ./development/programming-languages.nix
    ./development/opencode.nix
    ./development/web-testing.nix
    ./development/ai-coding-tools.nix

    ./gaming/gaming.nix
    ./gaming/gaming-hdr.nix
    ./gaming/scopebuddy.nix

    ./services/nfs-server.nix
    ./services/nfs-cluster-mounts.nix
    ./services/nfs-state-sync.nix
    ./services/nfs-client.nix
    ./services/tplink-switches.nix
    ./services/tplink-cli.nix
    ./services/lm-studio.nix
    ./services/lm-studio-headless.nix
    ./services/llamafile.nix
    ./services/stability-matrix.nix
    ./services/appimage-updater.nix
    ./services/haven-desktop.nix
    ./services/nixos-share.nix
    ./services/podman-auto-update.nix
    ./services/nextcloud.nix
    ./services/service-gateway.nix
    ./services/host-dashboard.nix
    ./services/ci-runner.nix
    ./services/garnix.nix
    ./services/hermes-cli.nix
    ./services/auto-update.nix
    ./services/whisper-dictation.nix
    ./services/voxtype.nix
    ./services/cloudflared.nix
    ./services/cluster-ca.nix
    ./services/cluster-services.nix
    ./services/unbound-common.nix
    ./services/syncthing.nix
    ./services/garage.nix
    ./services/backup-to-garage.nix
    ./services/binary-cache.nix
    ./services/rclone.nix
    ./services/vaultwarden.nix
    ./services/casdoor.nix
    ./services/central-auth.nix
    ./services/self-healing-alerts.nix

    ./services/monitoring/default.nix
    ./services/gpu-exporters.nix    ./multimedia/gstreamer.nix
    ./desktop/spotify-spotx.nix
    ./system/distributed-builds.nix
    ./system/flake-lock-sync.nix
    ./system/nixos-fallback-cache.nix
    ./profiles/default.nix
    ./profiles/node-profiles.nix

    ./network/cluster-hosts.nix
    ./network/cluster-dns.nix
    ./networking/cluster-networking.nix
    ./services/claude-code-router.nix
    ./services/supply-chain-cooldowns.nix
    ./services/container-scanning.nix
    ./services/vane.nix
    ./services/k8s-nix-deploy.nix
    ./services/brain-research.nix
  ];
}
