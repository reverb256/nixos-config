{ config, lib, pkgs, utils, ... }: {
  disko.devices = {
    disk.nvme0n1 = {
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
                "@root" = {
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

    disk.nvme1n1 = {
      device = "/dev/disk/by-id/nvme-XPG_GAMMIX_S11_Pro_2J2520059477";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          swap = {
            size = "16G";
            content = { type = "swap"; discardPolicy = "both"; };
          };
          data = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];
              subvolumes = {
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
                "@persistent" = {
                  mountpoint = "/persistent";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
                "@games" = {
                  mountpoint = "/games";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems = {
    "/persistent" = { neededForBoot = true; };
    "/nix" = { neededForBoot = true; };
    "/home" = { neededForBoot = true; };
    "/games" = { neededForBoot = false; };
  };
}