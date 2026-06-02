{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  btrfsDevice = "/dev/disk/by-partlabel/disk-nvme1n1-root";
  btrfsDeviceUnit = "${utils.escapeSystemdPath btrfsDevice}.device";
in {
  disko.devices = {
    disk.nvme1n1 = {
      device = btrfsDevice;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
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
            size = "16G";
            content = {
              type = "swap";
              discardPolicy = "both";
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
                "@persistent" = {
                  mountpoint = "/persistent";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
                "@nix" = {
                  mountpoint = "/nix";
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
  };

  fileSystems = {
    "/persistent" = {neededForBoot = true;};
    "/nix" = {neededForBoot = true;};
    "/home" = {neededForBoot = true;};
  };

  # Root rotation DISABLED — @root is now persistent.
  # The rd.systemd.mask kernel parameter prevents the old initrd service from running.
  # Next nixos-rebuild switch will remove the service entirely from the initrd.
}
