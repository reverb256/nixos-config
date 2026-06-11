{ config, lib, pkgs, utils, ... }: {
  disko.devices = {
    disk.samsung = {
      # Samsung SSD 980 1TB — root filesystem (labeled "root")
      device = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S64ANJ0R712954W";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["fmask=0077" "dmask=0077"];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];
              subvolumes = {
                "@" = {
                  mountpoint = "/";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
              };
            };
          };
        };
      };
    };

    disk.xpg = {
      # XPG GAMMIX S11 Pro — nix store + var (labeled "nix")
      device = "/dev/disk/by-id/nvme-XPG_GAMMIX_S11_Pro_2J2520059477";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          swap = {
            size = "16G";
            content = { type = "swap"; };
          };
          nix = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];
              subvolumes = {
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
                "@var" = {
                  mountpoint = "/var";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
                "@games" = {
                  mountpoint = "/data/games";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime" "nofail"];
                };
                "@projects" = {
                  mountpoint = "/data/projects";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime" "nofail"];
                };
              };
            };
          };
        };
      };
    };
  };

  # neededForBoot — filesystems that MUST mount before stage-2 runs
  # This is the critical fix that prevents the "can't find closure" boot failure
  fileSystems = {
    "/nix" = { neededForBoot = true; };
    "/var" = { neededForBoot = true; };
  };

  # Child subvolumes (srv, tmp, @var/tmp, @var/lib/*) are nested under @ or @var
  # and auto-mounted through their parent — no separate entries needed.
  #
  # Bind mount /data/hermes → /home/j_kro/.hermes is kept in configuration.nix
  # (disko doesn't manage bind mounts).
  #
  # swap on nvme0n1p1 exists but is unused — zramSwap handles swap instead.
}
