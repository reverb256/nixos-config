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

    # Use systemd's built-in restart policies instead of manual recovery scripts
    systemd.services.nix-daemon = {
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 5;
        StartLimitBurst = 5;
        StartLimitIntervalSec = 60;
      };
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
