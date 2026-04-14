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
    environment.systemPackages = with pkgs; [
      duperemove
      compsize
      btrfs-progs
    ];

    systemd = {
      services = {
        btrfs-dedup-all = {
          description = "BTRFS deduplication scan for all filesystems";
          path = [pkgs.btrfs-progs pkgs.duperemove];
          script = ''
            pgrep -f "duperemove.*-r" && exit 0

            echo "[$(date)] Starting BTRFS deduplication scan" | tee -a /var/log/btrfs-dedup.log

            for mount in $(findmnt -t btrfs -n -o TARGET --target /data / /home 2>/dev/null); do
              echo "Scanning $mount..." | tee -a /var/log/btrfs-dedup.log
              duperemove -r -d -h --skip-size=256K "$mount" 2>&1 | tee -a /var/log/btrfs-dedup.log || true
            done

            echo "[$(date)] BTRFS deduplication scan completed" | tee -a /var/log/btrfs-dedup.log
          '';
          startAt = "Sat 02:00";
          serviceConfig = {
            Type = "oneshot";
            Nice = 15;
            IOSchedulingClass = "idle";
            IOSchedulingPriority = 7;
            LogLevelMax = "info";
          };
        };

        btrfs-scrub-all = {
          description = "Monthly BTRFS scrub for all filesystems";
          path = [pkgs.btrfs-progs];
          script = ''
            echo "[$(date)] Starting BTRFS scrub for all filesystems" | tee -a /var/log/btrfs-scrub.log

            for fs in $(findmnt -t btrfs -n -o TARGET --target / /home /data 2>/dev/null); do
              echo "Scrubbing $fs..." | tee -a /var/log/btrfs-scrub.log
              btrfs scrub start -B -R "$fs" 2>&1 | tee -a /var/log/btrfs-scrub.log || true
            done

            echo "[$(date)] BTRFS scrub completed" | tee -a /var/log/btrfs-scrub.log
          '';
          startAt = "Mon 03:00";
          serviceConfig = {
            Type = "oneshot";
            Nice = 15;
            IOSchedulingClass = "idle";
          };
        };

        btrfs-balance-all = {
          description = "Monthly BTRFS balance for all filesystems";
          path = [pkgs.btrfs-progs];
          script = ''
            echo "[$(date)] Starting BTRFS balance for all filesystems" | tee -a /var/log/btrfs-balance.log

            for fs in $(findmnt -t btrfs -n -o TARGET --target / /home /data 2>/dev/null); do
              echo "Balancing $fs..." | tee -a /var/log/btrfs-balance.log
              btrfs balance start -dusage=75 -musage=75 "$fs" 2>&1 | tee -a /var/log/btrfs-balance.log || true
            done

            echo "[$(date)] BTRFS balance completed" | tee -a /var/log/btrfs-balance.log
          '';
          startAt = "Sun 03:00";
          serviceConfig = {
            Type = "oneshot";
            Nice = 15;
            IOSchedulingClass = "idle";
          };
        };
      };

      timers = {
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

      tmpfiles.rules = [
        "d /var/log 0755 root root -"
        "f /var/log/btrfs-dedup.log 0644 root root -"
        "f /var/log/btrfs-scrub.log 0644 root root -"
        "f /var/log/btrfs-balance.log 0644 root root -"
      ];
    };

    environment.etc."btrfs-compression/README.md".text = ''

      - Text files: 60-80% reduction
      - JSON/YAML: 70-90% reduction
      - Logs: 80-90% reduction
      - Binaries: 10-30% reduction
      - **Overall: 20-40% space savings**

      - **Weekly**: Deduplication scan (all BTRFS) - Saturdays 2 AM
      - **Monthly**: Scrub (data integrity check) - Mondays 3 AM
      - **Monthly**: Balance (defragmentation) - Sundays 3 AM

      compsize /data/@projects/some-file.txt

      compsize /data/@projects

      sudo duperemove -r -d -h /data

      sudo btrfs scrub start /

      sudo btrfs scrub status /

      sudo btrfs balance start -dusage=75 /data

      sudo duperemove -r -d /data/@projects/trovesandcoves

      compsize .

      findmnt -t btrfs

      btrfs filesystem df /

      sudo btrfs balance start -dcompress=2 /
    '';
  };
}
