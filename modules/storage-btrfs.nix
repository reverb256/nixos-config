# Unified Btrfs Subvolume Management Module
# Provides declarative, unified storage configuration across all cluster nodes
# Each host can enable/disable subvolumes based on their specific needs
{
  lib,
  pkgs,
  config,
  ...
}:
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

    systemd.tmpfiles.settings = {
      "btrfs-subvolumes" = {
        "/data" = {
          d = {
            mode = "0755";
            user = "root";
            group = "root";
          };
        };
        "/home/j_kro/projects" = {
          d = {
            mode = "0755";
            user = "root";
            group = "root";
          };
        };
        "/home/j_kro/.cache" = {
          d = {
            mode = "0755";
            user = "root";
            group = "root";
          };
        };
        "/home/j_kro/Media" = {
          d = {
            mode = "0755";
            user = "root";
            group = "root";
          };
        };
        "/home/j_kro/.snapshots" = {
          d = {
            mode = "0755";
            user = "root";
            group = "root";
          };
        };
      };
    };

    # Auto-scrub service
    systemd.timers.btrfs-scrub = mkIf cfg.autoScrub.enable {
      description = "Timer for periodic Btrfs scrub";
      wantedBy = ["multi-user.target"];
      timerConfig = {
        OnCalendar = cfg.autoScrub.schedule;
        Persistent = true;
      };
    };

    systemd.services.btrfs-scrub = mkIf cfg.autoScrub.enable {
      description = "Periodic Btrfs scrub for data integrity";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.btrfs-progs}/bin/btrfs scrub start -B -c ${cfg.subvolumes.device}";
      };
    };

    # Auto-balance service
    systemd.services.btrfs-balance = mkIf cfg.autoBalance.enable {
      description = "Periodic Btrfs balance to maintain filesystem health";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.btrfs-progs}/bin/btrfs balance start -dusage=${toString cfg.autoBalance.threshold}% ${cfg.subvolumes.device}";
        ExecCondition = "${pkgs.btrfs-progs}/bin/btrfs filesystem usage ${cfg.subvolumes.device} | awk '/Device/ {gsub(/,/,\"$\"); if ($2+0) > ${toString cfg.autoBalance.threshold} { exit 0 } exit 1 }'";
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
    systemd.services.btrfs-subvolumes =
      mkIf (
        cfg.subvolumes."@data".enable
        || cfg.subvolumes."@projects".enable
        || cfg.subvolumes."@cache".enable
        || cfg.subvolumes."@media".enable
        || cfg.subvolumes."@snapshots".enable
      ) {
        description = "Ensure Btrfs subvolumes exist";
        path = [
          pkgs.writeShellScriptBin
          "btrfs-create-subvolumes"
          ''
            #!/bin/sh
            set -e

            DEVICE="${cfg.subvolumes.device}"
            ROOT_MOUNT="/run/btrfs-root"

            # Mount device temporarily
            mount -t btrfs "$DEVICE" "$ROOT_MOUNT"

            # Create subvolumes if they don't exist
            ${optionalString cfg.subvolumes."@data".enable ''
              btrfs subvolume list "$ROOT_MOUNT" | grep -q '@data' || \
                btrfs subvolume create "$ROOT_MOUNT/@data"
            ''}

            ${optionalString cfg.subvolumes."@projects".enable ''
              btrfs subvolume list "$ROOT_MOUNT" | grep -q '@projects' || \
                btrfs subvolume create "$ROOT_MOUNT/@projects"
            ''}

            ${optionalString cfg.subvolumes."@cache".enable ''
              btrfs subvolume list "$ROOT_MOUNT" | grep -q '@cache' || \
                btrfs subvolume create "$ROOT_MOUNT/@cache"
            ''}

            ${optionalString cfg.subvolumes."@media".enable ''
              btrfs subvolume list "$ROOT_MOUNT" | grep -q '@media' || \
                btrfs subvolume create "$ROOT_MOUNT/@media"
            ''}

            ${optionalString cfg.subvolumes."@snapshots".enable ''
              btrfs subvolume list "$ROOT_MOUNT" | grep -q '@snapshots' || \
                btrfs subvolume create "$ROOT_MOUNT/@snapshots"
            ''}

            # Unmount
            umount "$ROOT_MOUNT"
          ''
        ];

        script = ''
          # Run on boot and when module is enabled
          ${pkgs.btrfs-create-subvolumes}/bin/btrfs-create-subvolumes
        '';

        wantedBy = ["multi-user.target"];
        after = ["local-fs.target"];
      };

    # Create filesystem mounts for enabled subvolumes
    fileSystems = mkMerge [
      # @data - User data (Zephyr only)
      (mkIf cfg.subvolumes."@data".enable {
        "/data" = {
          inherit (cfg.subvolumes) device;
          fsType = "btrfs";
          options = ["subvol=@data"];
        };
      })

      # @projects - Development projects
      (mkIf cfg.subvolumes."@projects".enable {
        "/home/j_kro/projects" = {
          inherit (cfg.subvolumes) device;
          fsType = "btrfs";
          options = ["subvol=@projects"];
        };
      })

      # @cache - Build/cache data
      (mkIf cfg.subvolumes."@cache".enable {
        "/home/j_kro/.cache" = {
          inherit (cfg.subvolumes) device;
          fsType = "btrfs";
          options = ["subvol=@cache"];
        };
      })

      # @media - Media files
      (mkIf cfg.subvolumes."@media".enable {
        "/home/j_kro/Media" = {
          inherit (cfg.subvolumes) device;
          fsType = "btrfs";
          options = ["subvol=@media"];
        };
      })

      # @snapshots - Btrfs snapshots
      (mkIf cfg.subvolumes."@snapshots".enable {
        "/home/j_kro/.snapshots" = {
          inherit (cfg.subvolumes) device;
          fsType = "btrfs";
          options = ["subvol=@snapshots"];
        };
      })
    ];
  };
}
