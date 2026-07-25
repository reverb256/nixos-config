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
    device = "/dev/disk/by-uuid/E979-C61E";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  # Swap partitions
  swapDevices = [
    {
      device = "/dev/disk/by-uuid/6fba2143-d725-4b5b-836c-98b7cedca5ee";
    }
    {
      device = "/dev/disk/by-uuid/835adbd3-7cae-46e9-8f85-772f77724b90";
    }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
