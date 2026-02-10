# Unified Btrfs Subvolume Management Module
# Provides declarative, unified storage configuration across all cluster nodes
# Each host can enable/disable subvolumes based on their specific needs
{lib, pkgs, ...}:
with lib; let
  cfg = config.storage-btrfs;
in {
  options.storage-btrfs = {
    enable = mkEnableOption "Btrfs subvolume management";

    subvolumes = {
      "@" = mkEnableOption "Root subvolume (@)";
      "@home" = mkEnableOption "User home subvolume (@home)";
      "@data" = mkEnableOption "User data subvolume (@data)";
      "@projects" = mkEnableOption "Development projects subvolume (@projects)";
      "@cache" = mkEnableOption "Build/cache subvolume (@cache)";
      "@media" = mkEnableOption "Media files subvolume (@media)";
      "@snapshots" = mkEnableOption "Btrfs snapshots subvolume (@snapshots)";

      device = mkOption {
        type = types.str;
        description = "Root btrfs device (used for all subvolumes)";
      };
    };

    autoScrub = {
      enable = mkEnableOption "Automatic Btrfs scrub for maintenance";
      schedule = mkOption {
        type = types.str;
        default = "monthly";
        description = "Systemd timer format (weekly, monthly, etc.)";
      };
    };

    autoBalance = {
      enable = mkEnableOption "Automatic Btrfs balance";
      schedule = mkOption {
        type = types.str;
        default = "monthly";
        description = "Systemd timer format (weekly, monthly, etc.)";
      };
      threshold = mkOption {
        type = types.ints.between 5 30;
        default = 10;
        description = "Percentage difference before balancing (5-30%)";
      };
    };
  };

  config = mkIf cfg.enable {
    # Btrfs utilities
    environment.systemPackages = with pkgs; [
      btrfs-progs
    ];

    # Create subvolumes for enabled options
    # Note: @ and @home are always created by NixOS
    # Additional subvolumes are created declaratively

    systemd.tmpfiles.rules =
      # Create mount points
      (lib.optional cfg.subvolumes."@data" "d ${cfg.subvolumes.device} 0755 root root -")
      ++ (lib.optional cfg.subvolumes."@projects" "d ${cfg.subvolumes.device} 0755 root root -")
      ++ (lib.optional cfg.subvolumes."@cache" "d ${cfg.subvolumes.device} 0755 root root -")
      ++ (lib.optional cfg.subvolumes."@media" "d ${cfg.subvolumes.device} 0755 root root -")
      ++ (lib.optional cfg.subvolumes."@snapshots" "d ${cfg.subvolumes.device} 0755 root root -")
    );

    # Auto-scrub service
    services.btrfs.autoScrub = mkIf cfg.autoScrub.enable {
      enable = true;
      fileSystems = lib.flatten (lib.mapAttrsToList (name: enable: cfg.subvolumes."${name}") ([
        cfg.subvolumes."@".device
        cfg.subvolumes."@home".device
      ]));
      interval = cfg.autoScrub.schedule;
    };

    # Auto-balance service (periodic rebalancing)
    systemd.services.btrfs-balance = mkIf cfg.autoBalance.enable {
      description = "Periodic Btrfs balance to maintain filesystem health";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.btrfs-progs}/bin/btrfs balance start -dusage=${toString cfg.autoBalance.threshold}% ${cfg.subvolumes.device}";
        # Only run if usage threshold is exceeded
        ExecCondition = ''${pkgs.btrfs-progs}/bin/btrfs filesystem usage ${cfg.subvolumes.device} | awk '/Device/ {gsub(/,/,$2); if ($2+0) > ${toString cfg.autoBalance.threshold} { exit 0 } exit 1 }'';
      };
    };

    systemd.timers.btrfs-balance = mkIf cfg.autoBalance.enable {
      description = "Timer for periodic Btrfs balance";
      wantedBy = ["multi-user.target"];
      timerConfig = {
        OnCalendar = cfg.autoBalance.schedule;
        Persistent = true;
      };
    };

    # Btrfs subvolume management service
    systemd.services.btrfs-subvolumes = mkIf (
      cfg.subvolumes."@data".enable ||
      cfg.subvolumes."@projects".enable ||
      cfg.subvolumes."@cache".enable ||
      cfg.subvolumes."@media".enable ||
      cfg.subvolumes."@snapshots".enable
    ) {
      description = "Ensure Btrfs subvolumes exist";
      path = [pkgs.writeShellScriptBin "btrfs-create-subvolumes" ''
        #!/bin/sh
        set -e

        DEVICE="${cfg.subvolumes.device}"
        ROOT_MOUNT="/run/btrfs-root"

        # Mount device temporarily
        mount -t btrfs "$DEVICE" "$ROOT_MOUNT"

        # Create subvolumes if they don't exist
        ${lib.optionalString cfg.subvolumes."@data".enable ''
          btrfs subvolume list "$ROOT_MOUNT" | grep -q '@data' || \
            btrfs subvolume create "$ROOT_MOUNT/@data"
        ''}

        ${lib.optionalString cfg.subvolumes."@projects".enable ''
          btrfs subvolume list "$ROOT_MOUNT" | grep -q '@projects' || \
            btrfs subvolume create "$ROOT_MOUNT/@projects"
        ''}

        ${lib.optionalString cfg.subvolumes."@cache".enable ''
          btrfs subvolume list "$ROOT_MOUNT" | grep -q '@cache' || \
            btrfs subvolume create "$ROOT_MOUNT/@cache"
        ''}

        ${lib.optionalString cfg.subvolumes."@media".enable ''
          btrfs subvolume list "$ROOT_MOUNT" | grep -q '@media' || \
            btrfs subvolume create "$ROOT_MOUNT/@media"
        ''}

        ${lib.optionalString cfg.subvolumes."@snapshots".enable ''
          btrfs subvolume list "$ROOT_MOUNT" | grep -q '@snapshots' || \
            btrfs subvolume create "$ROOT_MOUNT/@snapshots"
        ''}

        # Unmount
        umount "$ROOT_MOUNT"
      ''};

      script = ''
        # Run on boot and when module is enabled
        ${pkgs.btrfs-create-subvolumes}/bin/btrfs-create-subvolumes
      '';

      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];
    };

    # Create filesystem mounts for enabled subvolumes
    fileSystems = lib.mkMerge [
      # @data - User data (Zephyr only)
      (lib.mkIf cfg.subvolumes."@data".enable {
        "/data" = {
          device = cfg.subvolumes.device;
          fsType = "btrfs";
          options = ["subvol=@data"];
        };
      })

      # @projects - Development projects
      (lib.mkIf cfg.subvolumes."@projects".enable {
        "/home/j_kro/projects" = {
          device = cfg.subvolumes.device;
          fsType = "btrfs";
          options = ["subvol=@projects"];
        };
      })

      # @cache - Build/cache data
      (lib.mkIf cfg.subvolumes."@cache".enable {
        "/home/j_kro/.cache" = {
          device = cfg.subvolumes.device;
          fsType = "btrfs";
          options = ["subvol=@cache"];
        };
      })

      # @media - Media files
      (lib.mkIf cfg.subvolumes."@media".enable {
        "/home/j_kro/Media" = {
          device = cfg.subvolumes.device;
          fsType = "btrfs";
          options = ["subvol=@media"];
        };
      })

      # @snapshots - Btrfs snapshots
      (lib.mkIf cfg.subvolumes."@snapshots".enable {
        "/home/j_kro/.snapshots" = {
          device = cfg.subvolumes.device;
          fsType = "btrfs";
          options = ["subvol=@snapshots"];
        };
      })
    ];
  };
}
