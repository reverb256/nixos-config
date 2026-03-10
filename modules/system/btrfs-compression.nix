# BTRFS Compression and Deduplication Configuration
# Enables zstd compression for BTRFS filesystems and sets up deduplication tools
{
  config,
  lib,
  pkgs,
  ...
}: {
  options.hardware.btrfs-compression = {
    enable = lib.mkEnableOption "BTRFS zstd compression and deduplication tools";
  };

  config = lib.mkIf config.hardware.btrfs-compression.enable {
    # ============================================================================
    # FILESYSTEM MOUNT OPTIONS - Add compression to existing BTRFS mounts
    # ============================================================================
    fileSystems = {
      "/" = {
        # Root filesystem - add compression to existing options
        options = lib.mkOptionDefault [
          "subvol=@"
          "compress=zstd:3"
          "ssd"
          "discard=async"
          "space_cache=v2"
        ];
      };

      "/home" = {
        # Home filesystem - add compression
        options = lib.mkOptionDefault [
          "subvol=@home"
          "compress=zstd:3"
          "ssd"
          "discard=async"
          "space_cache=v2"
        ];
      };

      "/data" = {
        # Data filesystem on second drive - add compression
        options = lib.mkOptionDefault [
          "compress=zstd:3"
          "ssd"
          "discard=async"
          "space_cache=v2"
        ];
      };
    };

    # ============================================================================
    # SYSTEM PACKAGES - Deduplication and BTRFS tools
    # ============================================================================
    environment.systemPackages = with pkgs; [
      # BTRFS deduplication tools
      duperemove       # Block-level deduplication (run manually or via cron)
      btrfsmaintenance  # Periodic BTRFS maintenance tasks
      compsize         # Check compression ratio on files/directories
      btrfs-progs      # BTRFS utilities (already in system-packages)
    ];

    # ============================================================================
    # SYSTEMD SERVICES - Periodic deduplication and maintenance
    # ============================================================================
    systemd.services = {
      # Weekly deduplication scan for /data (where projects live)
      btrfs-dedup-data = {
        description = "BTRFS deduplication scan for /data";
        path = [pkgs.btrfs-progs pkgs.duperemove];
        script = ''
          # Skip if dedup is already running
          pgrep -f "duperemove.*-r /data" && exit 0

          # Log start time
          echo "[$(date)] Starting BTRFS deduplication scan for /data" | tee -a /var/log/btrfs-dedup.log

          # Run deduplication with quiet mode, skip files < 100KB
          # -r: recursive scan
          # -d: deduplicate mode
          # --skip-size: skip files smaller than this (default 100K)
          # -h: print human-readable sizes
          duperemove -r -d -h --skip-size=256K /data 2>&1 | tee -a /var/log/btrfs-dedup.log

          echo "[$(date)] BTRFS deduplication scan completed" | tee -a /var/log/btrfs-dedup.log
        '';
        startAt = "Sat 02:00";  # Saturday 2 AM
        serviceConfig = {
          Type = "oneshot";
          Nice = 15;  # Low priority to avoid impacting system performance
          IOSchedulingClass = "idle";
          IOSchedulingPriority = 7;
          LogLevelMax = "info";  # Reduce log spam
        };
      };

      # Monthly BTRFS scrub (detect and repair data corruption)
      btrfs-scrub-root = {
        description = "Monthly BTRFS scrub for root filesystem";
        path = [pkgs.btrfs-progs];
        script = ''
          echo "[$(date)] Starting BTRFS scrub for /" | tee -a /var/log/btrfs-scrub.log
          btrfs scrub start -B -R /
          echo "[$(date)] BTRFS scrub for / completed" | tee -a /var/log/btrfs-scrub.log
        '';
        startAt = "Mon 03:00";  # First Monday of each month at 3 AM
        serviceConfig = {
          Type = "oneshot";
          Nice = 15;
          IOSchedulingClass = "idle";
        };
      };

      btrfs-scrub-data = {
        description = "Monthly BTRFS scrub for data filesystem";
        path = [pkgs.btrfs-progs];
        script = ''
          echo "[$(date)] Starting BTRFS scrub for /data" | tee -a /var/log/btrfs-scrub.log
          btrfs scrub start -B -R /data
          echo "[$(date)] BTRFS scrub for /data completed" | tee -a /var/log/btrfs-scrub.log
        '';
        startAt = "Mon 04:00";  # First Monday of each month at 4 AM
        serviceConfig = {
          Type = "oneshot";
          Nice = 15;
          IOSchedulingClass = "idle";
        };
      };

      # Monthly balance (reclaim space and improve fragmentation)
      btrfs-balance = {
        description = "Monthly BTRFS balance for all filesystems";
        path = [pkgs.btrfs-progs];
        script = ''
          echo "[$(date)] Starting BTRFS balance" | tee -a /var/log/btrfs-balance.log

          # Balance with usage threshold (only chunks with <75% usage)
          # This reclaims space and reduces fragmentation
          btrfs balance start -dusage=75 -musage=75 / 2>&1 | tee -a /var/log/btrfs-balance.log
          btrfs balance start -dusage=75 -musage=75 /home 2>&1 | tee -a /var/log/btrfs-balance.log
          btrfs balance start -dusage=75 -musage=75 /data 2>&1 | tee -a /var/log/btrfs-balance.log

          echo "[$(date)] BTRFS balance completed" | tee -a /var/log/btrfs-balance.log
        '';
        startAt = "Sun 03:00";  # Sunday 3 AM
        serviceConfig = {
          Type = "oneshot";
          Nice = 15;
          IOSchedulingClass = "idle";
        };
      };
    };

    # ============================================================================
    # TIMERS - Enable the scheduled services
    # ============================================================================
    systemd.timers = {
      btrfs-dedup-data = {
        wantedBy = ["timers.target"];
        partOf = ["btrfs-dedup-data.service"];
        timerConfig.Persistent = true;
      };

      btrfs-scrub-root = {
        wantedBy = ["timers.target"];
        partOf = ["btrfs-scrub-root.service"];
        timerConfig.Persistent = true;
      };

      btrfs-scrub-data = {
        wantedBy = ["timers.target"];
        partOf = ["btrfs-scrub-data.service"];
        timerConfig.Persistent = true;
      };

      btrfs-balance = {
        wantedBy = ["timers.target"];
        partOf = ["btrfs-balance.service"];
        timerConfig.Persistent = true;
      };
    };

    # ============================================================================
    # LOGGING
    # ============================================================================
    # Ensure log files exist and are rotated
    systemd.tmpfiles.settings = {
      "btrfs-maintenance-logs" = {
        "/var/log/btrfs-dedup.log" = {
          mode = "0644";
          user = "root";
          group = "root";
        };
        "/var/log/btrfs-scrub.log" = {
          mode = "0644";
          user = "root";
          group = "root";
        };
        "/var/log/btrfs-balance.log" = {
          mode = "0644";
          user = "root";
          group = "root";
        };
      };
    };

    # ============================================================================
    # DOCUMENTATION
    # ============================================================================
    environment.etc."btrfs-compression/README.md".text = ''
      # BTRFS Compression and Deduplication
      # ZSTD compression level 3 provides the best balance of ratio vs speed
      # Level | Ratio | Speed | Use Case
      # ------|-------|-------| ----------
      # 1     | Good  | Fastest | Real-time compression
      # 3     | Great | Fast   | **Default (sweet spot)**
      # 15    | Best  | Slow   | Archival storage

      ## Compression Benefits
      - Text files: 60-80% reduction
      - JSON/YAML: 70-90% reduction
      - Logs: 80-90% reduction
      - Binaries: 10-30% reduction
      - **Overall: 20-40% space savings**

      ## Scheduled Tasks
      - **Weekly**: Deduplication scan (/data) - Saturdays 2 AM
      - **Monthly**: Scrub (data integrity check) - Mondays 3-4 AM
      - **Monthly**: Balance (defragmentation) - Sundays 3 AM

      ## Manual Commands
      # Check compression ratio for a file
      compsize /data/@projects/some-file.txt

      # Check compression ratio for a directory
      compsize /data/@projects

      # Run deduplication manually
      sudo duperemove -r -d -h /data

      # Run scrub manually (data integrity check)
      sudo btrfs scrub start /

      # Check scrub status
      sudo btrfs scrub status /

      # Run balance manually
      sudo btrfs balance start -dusage=75 /data

      # Deduplicate specific directory
      sudo duperemove -r -d /data/@projects/trovesandcoves
    '';
  };
}
