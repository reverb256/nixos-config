{
  lib,
  pkgs,
  ...
}:
{
  disko.devices = {
    disk.nvme1n1 = {
      device = "/dev/nvme1n1";
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
              extraArgs = [ "-f" ];
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
    "/persistent" = { neededForBoot = true; };
    "/nix" = { neededForBoot = true; };
    "/home" = { neededForBoot = true; };
    "/etc" = { neededForBoot = true; };
    "/var" = { neededForBoot = true; };
    "/var/lib" = { neededForBoot = true; };
  };

  # BTRFS impermanence: recreate root subvolume each boot via systemd service
  # (systemd stage 1 doesn't support boot.initrd.postResumeCommands)
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.services.impermanence-root-rotate = {
    description = "Rotate ephemeral BTRFS root subvolume";
    requiredBy = [ "initrd-root-device.target" ];
    before = [ "sysroot.mount" ];
    after = [ "dev-nvme1n1p3.device" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    path = with pkgs; [ btrfs-progs coreutils findutils util-linux ];
    script = ''
      mkdir -p /btrfs_tmp
      mount -t btrfs -o subvol=/ /dev/nvme1n1p3 /btrfs_tmp

      if [[ -e /btrfs_tmp/@root ]]; then
        mkdir -p /btrfs_tmp/old_roots

        timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/@root)" "+%Y-%m-%-d_%H:%M:%S")
        mv /btrfs_tmp/@root "/btrfs_tmp/old_roots/$timestamp"

        # Delete old roots older than 30 days
        find /btrfs_tmp/old_roots/ -maxdepth 1 -mindepth 1 -mtime +30 -exec \
          sh -c '
            for subvol; do
              btrfs subvolume list -o "$subvol" | cut -f 9- -d " " | \
                xargs -I{} btrfs subvolume delete "/btrfs_tmp/{}" 2>/dev/null
              btrfs subvolume delete "$subvol"
            done
          ' _ {} +

      fi

      btrfs subvolume create /btrfs_tmp/@root
      umount /btrfs_tmp
    '';
  };
}
