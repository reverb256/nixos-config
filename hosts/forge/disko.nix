{
  config,
  lib,
  pkgs,
  utils,
  ...
}: {
  disko.devices = {
    # System SSD: TEAM T253X2256G (sda, 238.5G)
    # Full OS — EFI, swap, root + nix + persistent + srv + var/tmp
    disk.sda = {
      device = "/dev/disk/by-id/ata-TEAM_T253X2256G_TM701907310240040386";
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
            content = {type = "swap";};
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

    # Storage HDD: ADATA SU635 (sdb, 223.6G)
    # /home and /storage (non-critical, nofail)
    disk.sdb = {
      device = "/dev/disk/by-id/ata-ADATA_SU635_2L40291DQ5CE";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          data = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];
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
    "/persistent" = {neededForBoot = true;};
    "/nix" = {neededForBoot = true;};
    "/home" = {neededForBoot = false;};
    "/storage" = {neededForBoot = false;};
    "/var/storage" = {neededForBoot = false;};
  };
}
