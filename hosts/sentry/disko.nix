{ config, lib, pkgs, utils, ... }: {
  disko.devices = {
    disk.sdb = {
      device = "/dev/disk/by-id/ata-Micron_1100_SATA_256GB_18361E518AB4";
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
          swap = {
            size = "8G";
            content = { type = "swap"; };
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
                "@persistent" = {
                  mountpoint = "/persistent";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
                # Implicit subvolumes (created by NixOS systemd)
                "@srv" = {
                  mountpoint = "/srv";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
                "@var/tmp" = {
                  mountpoint = "/var/tmp";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
              };
            };
          };
        };
      };
    };

    # HDD: Full disko management (declarative partitioning + formatting)
    disk.sda = {
      device = "/dev/disk/by-id/ata-ST1000DM010-2EP102_ZN1AMQLC";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          data = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];  # Formats the partition - DATA LOSS
              subvolumes = {
                "@" = {
                  mountpoint = "/storage";
                  mountOptions = ["compress=zstd" "nofail"];
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = ["compress=zstd" "nofail"];
                };
                "@var" = {
                  mountpoint = "/var/storage";
                  mountOptions = ["compress=zstd" "nofail"];
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
    "/home" = { neededForBoot = false; };
    "/storage" = { neededForBoot = false; };
    "/var/storage" = { neededForBoot = false; };
  };
}