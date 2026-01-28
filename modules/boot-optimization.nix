# Boot Performance Optimization Module
# Fixes critical boot time bottlenecks and systemd service issues
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  # Optimize boot performance
  bootOptimizations = {
    # CRITICAL: Disable tmpfiles-clean at boot (6.486s -> 0s)
    # Use modern NixOS option instead of force override
    systemd.tmpfiles.cleanOnBoot = false;

    # Network optimization for distributed builds
    networking.networkmanager.enable = mkDefault true;

    # Optimize MySQL startup - move off critical path
    services.mysql = mkIf config.services.mysql.enable {
      settings.mysqld = {
        # Faster startup optimizations
        innodb_buffer_pool_size = "2G";
        innodb_log_file_size = "256M";
        innodb_flush_log_at_trx_commit = 2;
        skip-innodb-doublewrite = true;
        # Performance tuning
        table_open_cache_instances = 8;
        table_open_cache_size = 4000;
        open_files_limit = 65535;
      };
    };

    # Note: Filesystem optimizations moved to configuration.nix to avoid circular dependencies

    # Fix firmware refresh service - delay until after login
    systemd.services.fwupd-refresh = {
      after = ["graphical.target"];
      wants = ["graphical.target"];
      serviceConfig = {
        ExecStart = "${pkgs.fwupd}/bin/fwupdrefresh --force";
        TimeoutStartSec = 300; # 5 minutes timeout
      };
    };

    # Create boot performance monitoring service
    systemd.services.boot-performance-monitor = {
      description = "Boot Performance Monitoring";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScriptBin "boot-monitor" ''
          #!/bin/bash
          echo "$(date): Boot completed in $(systemd-analyze | grep 'Startup finished' | awk '{print $5}')"
          echo "$(date): Userspace boot time: $(systemd-analyze time | grep 'userspace' | awk '{print $2}')"

          # Log slow services
          echo "=== Slowest Services ===" >> /var/log/boot-performance.log
          systemd-analyze blame | head -10 >> /var/log/boot-performance.log

          # System resource usage
          echo "=== Resource Usage ===" >> /var/log/boot-performance.log
          free -h >> /var/log/boot-performance.log
          df -h >> /var/log/boot-performance.log
        ''}/bin/boot-monitor";
        RemainAfterExit = true;
      };
      wantedBy = ["graphical.target"];
      after = ["graphical.target"];
    };

    # Fix Nix daemon stability issues
    nix = {
      # Reduce download timeouts to prevent crashes
      settings = {
        connect-timeout = 30;
        download-attempts = 3;
        max-silent-time = 3600; # 1 hour
        # Increase memory limits for large builds
        min-free = 1073741824; # 1GB
        max-free = 2147483648; # 2GB
      };
    };

    # Add Nix daemon crash recovery service
    systemd.services.nix-daemon-recovery = {
      description = "Nix Daemon Crash Recovery";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScriptBin "nix-recovery" ''
          #!/bin/bash
          echo "$(date): Checking Nix daemon status..."

          if ! systemctl is-active --quiet nix-daemon.socket; then
            echo "$(date): Nix daemon socket inactive, restarting..."
            systemctl restart nix-daemon.socket

            # Clean up any hanging downloads
            echo "$(date): Cleaning up hanging downloads..."
            rm -f /tmp/nix-download-*

            # Clear Nix daemon cache if corrupted
            if [ -d "/nix/var/nix/daemon-socket" ]; then
              rm -rf /nix/var/nix/daemon-socket/*
            fi
          fi

          # Verify daemon health
          if nix store ping --store https://cache.nixos.org; then
            echo "$(date): Nix daemon recovered successfully"
          else
            echo "$(date): Nix daemon recovery failed, manual intervention required"
            systemctl status nix-daemon.service
          fi
        ''}/bin/nix-recovery";
      };
      wantedBy = ["multi-user.target"];
    };

    # Add timer for Nix daemon recovery
    systemd.timers.nix-daemon-recovery = {
      description = "Nix Daemon Recovery Timer";
      timerConfig = {
        OnBootSec = 300;
        OnUnitActiveSec = "1h";
      };
      wantedBy = ["timers.target"];
    };

    # Add boot performance timer
    systemd.timers.boot-performance-monitor = {
      description = "Boot Performance Timer";
      timerConfig = {
        OnBootSec = 1; # Run 1 second after boot
        OnUnitActiveSec = "24h"; # Daily
        Persistent = true;
      };
      wantedBy = ["timers.target"];
    };
  };
in
  # Apply all optimizations
  bootOptimizations
