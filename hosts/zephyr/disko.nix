{ config, lib, pkgs, utils, ... }: {
  disko.devices = {
    disk.samsung = {
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
              mountOptions = ["nofail" "x-systemd.device-timeout=60s" "x-systemd.mount-timeout=60s"];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              subvolumes = {
                "@" = {
                  mountpoint = "/";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime" "nofail" "x-systemd.device-timeout=90s"];
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime" "nofail" "x-systemd.device-timeout=90s"];
                };
                "@/srv" = {
                  mountpoint = "/srv";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime" "nofail" "x-systemd.device-timeout=90s"];
                };
                "@/var/lib/portables" = {
                  mountpoint = "/var/lib/portables";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime" "nofail" "x-systemd.device-timeout=90s"];
                };
                "@/var/lib/machines" = {
                  mountpoint = "/var/lib/machines";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime" "nofail" "x-systemd.device-timeout=90s"];
                };
                "@/tmp" = {
                  mountpoint = "/tmp";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime" "nofail" "x-systemd.device-timeout=90s"];
                };
                "@/var/tmp" = {
                  mountpoint = "/var/tmp";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime" "nofail" "x-systemd.device-timeout=90s"];
                };
              };
            };
          };
        };
      };
    };

    disk.xpg = {
      device = "/dev/disk/by-id/nvme-XPG_GAMMIX_S11_Pro_2J2520059477";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          nix = {
            size = "100%";
            content = {
              type = "btrfs";
              subvolumes = {
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime" "nofail" "x-systemd.device-timeout=90s"];
                };
                "@var" = {
                  mountpoint = "/var";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime" "nofail" "x-systemd.device-timeout=90s"];
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems = {
    "/" = { neededForBoot = true; };
    "/nix" = { neededForBoot = true; };
    "/var" = { neededForBoot = true; };
  };

  systemd.settings = {
    Manager.DefaultTimeoutStartSec = 120;
    Manager.DefaultTimeoutStopSec = 90;
  };

  boot.loader.systemd-boot.configurationLimit = 8;
}