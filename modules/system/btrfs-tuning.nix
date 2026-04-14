{ config, lib, ... }: {
  boot.kernelParams = [
    "btrfs.commit_interval=300"
  ];
}
