{
  config,
  lib,
  pkgs,
  utils,
  ...
}: {
  disko.devices = {
    disk.sdb = {
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
              };
            };
          };
        };
      };
    };

    disk.sda = {
      device = "/dev/disk/by-id/ata-ADATA_SU635_2L40291DQ5CE";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          swap = {
            size = "8G";
            content = {type = "swap";};
          };
          data = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];
              subvolumes = {
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = ["compress=zstd:3" "ssd" "discard=async" "noatime"];
                };
                "@var" = {
                  mountpoint = "/var";
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
    "/var" = {neededForBoot = true;};
  };
}
