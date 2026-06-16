{ config, lib, pkgs, utils, ... }: {
  disko.devices = {
    disk.samsung = {
      # Samsung SSD 980 1TB — system drive (label "root")
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

    # XPG GAMMIX S11 Pro 1TB — secondary drive (label "nix")
    # Holds /nix, /var, /data/games, /data/projects
    disk.xpg = {
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
              extraArgs = ["-f"];  # WARNING: formats partition — data loss on disko apply
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

  fileSystems = {
    "/nix" = { neededForBoot = true; };
    "/var" = { neededForBoot = true; };
  };
}
