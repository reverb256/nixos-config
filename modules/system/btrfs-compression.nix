# BTRFS Compression and Deduplication Configuration
# Sets up deduplication tools and maintenance for all BTRFS filesystems
# Note: Mount options should be configured in hardware-configuration.nix or host configs
{
  config,
  lib,
  pkgs,
  ...
}: {
  options.hardware.btrfs-compression = {
    enable = lib.mkEnableOption "BTRFS zstd compression and deduplication tools for all filesystems";
  };

  config = lib.mkIf config.hardware.btrfs-compression.enable {
    # ============================================================================
    # SYSTEM PACKAGES - Deduplication and BTRFS tools
    # ============================================================================
    environment.systemPackages = with pkgs; [
      # BTRFS deduplication tools
      duperemove       # Block-level deduplication (run manually or via cron)
      compsize         # Check compression ratio on files/directories
      btrfs-progs      # BTRFS utilities
    ];

    # ============================================================================
    # SYSTEMD SERVICES - Periodic deduplication and maintenance
    # ============================================================================
    systemd.services = {
      # Weekly deduplication scan for all BTRFS filesystems
      btrfs-dedup-all = {
        description = "BTRFS deduplication scan for all filesystems";
        path = [pkgs.btrfs-progs pkgs.duperemove];
        script = ''
          # Skip if dedup is already running
          pgrep -f "duperemove.*-r" && exit 0

          # Log start time
          echo "[$(date)] Starting BTRFS deduplication scan" | tee -a /var/log/btrfs-dedup.log

          # Get all BTRFS mount points and run deduplication
          for mount in $(findmnt -t btrfs -n -o TARGET --target /data / /home 2>/dev/null); do
            echo "Scanning $mount..." | tee -a /var/log/btrfs-dedup.log
            # Run deduplication with quiet mode, skip files < 256KB
            # -r: recursive scan
            # -d: deduplicate mode
            # --skip-size: skip files smaller than this (default 100K)
            # -h: print human-readable sizes
            duperemove -r -d -h --skip-size=256K "$mount" 2>&1 | tee -a /var/log/btrfs-dedup.log || true
          done

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
      btrfs-scrub-all = {
        description = "Monthly BTRFS scrub for all filesystems";
        path = [pkgs.btrfs-progs];
        script = ''
          echo "[$(date)] Starting BTRFS scrub for all filesystems" | tee -a /var/log/btrfs-scrub.log

          # Scrub all mounted BTRFS filesystems
          for fs in $(findmnt -t btrfs -n -o TARGET --target / /home /data 2>/dev/null); do
            echo "Scrubbing $fs..." | tee -a /var/log/btrfs-scrub.log
            btrfs scrub start -B -R "$fs" 2>&1 | tee -a /var/log/btrfs-scrub.log || true
          done

          echo "[$(date)] BTRFS scrub completed" | tee -a /var/log/btrfs-scrub.log
        '';
        startAt = "Mon 03:00";  # Monday 3 AM
        serviceConfig = {
          Type = "oneshot";
          Nice = 15;
          IOSchedulingClass = "idle";
        };
      };

      # Monthly balance (reclaim space and improve fragmentation)
      btrfs-balance-all = {
        description = "Monthly BTRFS balance for all filesystems";
        path = [pkgs.btrfs-progs];
        script = ''
          echo "[$(date)] Starting BTRFS balance for all filesystems" | tee -a /var/log/btrfs-balance.log

          # Balance all mounted BTRFS filesystems with usage threshold
          # -dusage=75: only chunks with <75% usage
          # -musage=75: metadata chunks with <75% usage
          for fs in $(findmnt -t btrfs -n -o TARGET --target / /home /data 2>/dev/null); do
            echo "Balancing $fs..." | tee -a /var/log/btrfs-balance.log
            btrfs balance start -dusage=75 -musage=75 "$fs" 2>&1 | tee -a /var/log/btrfs-balance.log || true
          done

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
      btrfs-dedup-all = {
        wantedBy = ["timers.target"];
        partOf = ["btrfs-dedup-all.service"];
        timerConfig.Persistent = true;
      };

      btrfs-scrub-all = {
        wantedBy = ["timers.target"];
        partOf = ["btrfs-scrub-all.service"];
        timerConfig.Persistent = true;
      };

      btrfs-balance-all = {
        wantedBy = ["timers.target"];
        partOf = ["btrfs-balance-all.service"];
        timerConfig.Persistent = true;
      };
    };

    # ============================================================================
    # LOGGING
    # ============================================================================
    systemd.tmpfiles.rules = [
      "d /var/log 0755 root root -"
      "f /var/log/btrfs-dedup.log 0644 root root -"
      "f /var/log/btrfs-scrub.log 0644 root root -"
      "f /var/log/btrfs-balance.log 0644 root root -"
    ];

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
      - **Weekly**: Deduplication scan (all BTRFS) - Saturdays 2 AM
      - **Monthly**: Scrub (data integrity check) - Mondays 3 AM
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

      # Show compression stats for current directory
      compsize .

      # Show all BTRFS filesystems
      findmnt -t btrfs

      # Show compression stats for a specific filesystem
      btrfs filesystem df /

      # Force compression of existing files (requires balance)
      sudo btrfs balance start -dcompress=2 /
    '';
  };
}
