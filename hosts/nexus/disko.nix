{
  config,
  lib,
  pkgs,
  utils,
  ...
}: {
  disko.devices = {
    disk.nvme1n1 = {
      device = "/dev/disk/by-id/nvme-WDC_WDS100T2B0C-00PXH0_203797800744";
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
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
                "@nix" = {
                  mountpoint = "/nix";
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

  # Keep existing bcache0 array unchanged (managed outside disko)
  # /data/backups, /data/media, /data/shared, /var/lib/containers
  # These mount via fileSystems."..." in hardware.nix

  fileSystems = {
    "/persistent" = {neededForBoot = true;};
    "/nix" = {neededForBoot = true;};
    "/home" = {neededForBoot = true;};
    "/games" = {neededForBoot = false;};
  };
}
