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
    device = "/dev/disk/by-uuid/f7acac70-18fc-483a-b960-3c991c5124cf";
    fsType = "btrfs";
    options = ["subvol=@root" "compress=zstd:3" "ssd" "discard=async" "noatime"];
  };

  fileSystems."/persistent" = {
    device = "/dev/disk/by-uuid/f7acac70-18fc-483a-b960-3c991c5124cf";
    fsType = "btrfs";
    options = ["subvol=@persistent" "compress=zstd:3" "ssd" "discard=async" "noatime" "x-initrd.mount"];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/f7acac70-18fc-483a-b960-3c991c5124cf";
    fsType = "btrfs";
    options = ["subvol=@nix" "compress=zstd:3" "ssd" "discard=async" "noatime" "x-initrd.mount"];
  };

  # ADATA HDD (sda) - Home and Var
  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/4b0c9ba4-1cb5-4e9a-b750-191c2bd16c51";
    fsType = "btrfs";
    options = ["subvol=@home" "compress=zstd:3" "noatime"];
  };

  fileSystems."/var" = {
    device = "/dev/disk/by-uuid/4b0c9ba4-1cb5-4e9a-b750-191c2bd16c51";
    fsType = "btrfs";
    options = ["subvol=@var" "compress=zstd:3" "noatime" "x-initrd.mount"];
  };

  # Boot partition (TEAM SSD)
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/EB7C-E7CC";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  # Swap partitions
  swapDevices = [
    {
      device = "/dev/disk/by-uuid/b4655d1d-1abf-4c0f-a5f1-4fa5ba8d7d43";
    }
    {
      device = "/dev/disk/by-uuid/5f83b842-3e30-47f2-8274-8db86b7f7124";
    }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}