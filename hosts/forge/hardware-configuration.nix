{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" "rtsx_pci_sdmmc"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  # TEAM SSD (sdb) - Root, Persistent, Nix
  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/disk-sdb-root";
    fsType = "btrfs";
    options = ["subvol=@root" "compress=zstd:3" "ssd" "discard=async" "noatime"];
  };

  fileSystems."/persistent" = {
    device = "/dev/disk/by-partlabel/disk-sdb-root";
    fsType = "btrfs";
    options = ["subvol=@persistent" "compress=zstd:3" "ssd" "discard=async" "noatime" "x-initrd.mount"];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-partlabel/disk-sdb-root";
    fsType = "btrfs";
    neededForBoot = true;
    options = ["subvol=@nix" "compress=zstd:3" "ssd" "discard=async" "noatime" "x-initrd.mount"];
  };

  # ADATA HDD (sda) - Home and Var
  fileSystems."/home" = {
    device = "/dev/disk/by-partlabel/disk-sda-data";
    fsType = "btrfs";
    neededForBoot = true;
    options = ["subvol=@home" "compress=zstd:3" "noatime"];
  };

  fileSystems."/var" = {
    device = "/dev/disk/by-partlabel/disk-sda-data";
    fsType = "btrfs";
    options = ["subvol=@var" "compress=zstd:3" "noatime" "x-initrd.mount"];
  };

  # Boot partition (TEAM SSD)
  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/disk-sdb-boot";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  # Swap partitions
  swapDevices = [
    {
      device = "/dev/disk/by-partlabel/disk-sda-swap";
    }
    {
      device = "/dev/disk/by-partlabel/disk-sdb-swap";
    }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
