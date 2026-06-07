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

  # Samsung SSD 980 1TB (nvme0n1) - Root, Home, Boot
  fileSystems."/" = {
    device = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S64ANJ0R712954W-part2";
    fsType = "btrfs";
    options = ["subvol=@" "compress=zstd:3" "ssd" "discard=async" "noatime"];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S64ANJ0R712954W-part2";
    fsType = "btrfs";
    options = ["subvol=@home" "compress=zstd:3" "noatime"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S64ANJ0R712954W-part1";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  # XPG GAMMIX S11 Pro 2TB (nvme1n1) - Nix, Var
  fileSystems."/nix" = {
    device = "/dev/disk/by-id/nvme-XPG_GAMMIX_S11_Pro_2J2520059477-part2";
    fsType = "btrfs";
    options = ["subvol=@nix" "compress=zstd:3" "ssd" "discard=async" "noatime" "x-initrd.mount"];
  };

  fileSystems."/var" = {
    device = "/dev/disk/by-id/nvme-XPG_GAMMIX_S11_Pro_2J2520059477-part2";
    fsType = "btrfs";
    options = ["subvol=@var" "compress=zstd:3" "noatime" "x-initrd.mount"];
  };

  # Swap partitions
  swapDevices = [
    {
      device = "/dev/disk/by-id/nvme-XPG_GAMMIX_S11_Pro_2J2520059477-part1";
    }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}