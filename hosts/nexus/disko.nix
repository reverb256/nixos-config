{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  # Stable device identifier — survives NVMe name reordering across reboots.
  # Uses by-partlabel (set by disko during initial partitioning) which is
  # available early in the initrd before udev fully settles.
  # by-id symlinks were NOT available in systemd stage-1 initrd, causing
  # the impermanence-root-rotate service to hang waiting for the device unit.
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
              mountOptions = [
                "fmask=0077"
                "dmask=0077"
              ];
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
                # Ephemeral root — wiped each boot via impermanence
                "@root" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd:3"
                    "ssd"
                    "discard=async"
                    "noatime"
                  ];
                };

                # Persistent state — survives reboots
                "@persistent" = {
                  mountpoint = "/persistent";
                  mountOptions = [
                    "compress=zstd:3"
                    "ssd"
                    "discard=async"
                    "noatime"
                  ];
                };

                # Nix store — must survive reboots
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd:3"
                    "ssd"
                    "discard=async"
                    "noatime"
                  ];
                };

                # Home directories — persisted via impermanence module
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd:3"
                    "ssd"
                    "discard=async"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };

  # Impermanence requires these to be neededForBoot
  fileSystems = {
    "/persistent" = {neededForBoot = true;};
    "/nix" = {neededForBoot = true;};
    "/home" = {neededForBoot = true;};
  };

  # BTRFS impermanence: recreate root subvolume each boot via systemd service
  # (systemd stage 1 doesn't support boot.initrd.postResumeCommands)
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.initrdBin = with pkgs; [btrfs-progs coreutils findutils util-linuxMinimal];
  boot.initrd.systemd.services.impermanence-root-rotate = {
    description = "Rotate ephemeral BTRFS root subvolume";
    requiredBy = ["sysroot.mount"];
    before = ["sysroot.mount"];
    after = [btrfsDeviceUnit];
    unitConfig.DefaultDependencies = "no";
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "300";
      RemainAfterExit = true;
    };
    path = with pkgs; [btrfs-progs coreutils findutils util-linuxMinimal];
    script = ''
      mkdir -p /btrfs_tmp
      mount -t btrfs -o subvol=/ ${btrfsDevice} /btrfs_tmp

      if [[ -e /btrfs_tmp/@root ]]; then
        mkdir -p /btrfs_tmp/old_roots

        timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/@root)" "+%Y-%m-%-d_%H:%M:%S")
        mv /btrfs_tmp/@root "/btrfs_tmp/old_roots/$timestamp"

        # Delete old roots older than 30 days
        # Only delete btrfs subvolumes (inode 256) — skip regular directories
        find /btrfs_tmp/old_roots/ -maxdepth 1 -mindepth 1 -mtime +30 -exec \
          sh -c '
            for subvol; do
              inode=$(stat -c "%i" "$subvol" 2>/dev/null || echo 0)
              if [ "$inode" -ne 256 ]; then
                continue
              fi
              btrfs subvolume list -o "$subvol" 2>/dev/null | cut -f 9- -d " " | \
                xargs -I{} btrfs subvolume delete "/btrfs_tmp/{}" 2>/dev/null
              btrfs subvolume delete "$subvol" 2>/dev/null
            done
          ' _ {} +

      fi

      btrfs subvolume create /btrfs_tmp/@root
      umount /btrfs_tmp
    '';
  };
}
