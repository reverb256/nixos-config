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

  # Micron SSD (sdb) - Root, Persistent, Nix, Srv, Var/tmp
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/e1eee7b0-ba13-40b1-b147-6e544c92b302";
    fsType = "btrfs";
    options = ["subvol=@root" "compress=zstd:3" "ssd" "discard=async" "noatime"];
  };

  fileSystems."/persistent" = {
    device = "/dev/disk/by-uuid/e1eee7b0-ba13-40b1-b147-6e544c92b302";
    fsType = "btrfs";
    options = ["subvol=@persistent" "compress=zstd:3" "ssd" "discard=async" "noatime" "x-initrd.mount"];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/e1eee7b0-ba13-40b1-b147-6e544c92b302";
    fsType = "btrfs";
    options = ["subvol=@nix" "compress=zstd:3" "ssd" "discard=async" "noatime" "x-initrd.mount"];
  };

  fileSystems."/srv" = {
    device = "/dev/disk/by-uuid/e1eee7b0-ba13-40b1-b147-6e544c92b302";
    fsType = "btrfs";
    options = ["subvol=@srv" "compress=zstd:3" "ssd" "discard=async" "noatime" "x-initrd.mount"];
  };

  fileSystems."/var/tmp" = {
    device = "/dev/disk/by-uuid/e1eee7b0-ba13-40b1-b147-6e544c92b302";
    fsType = "btrfs";
    options = ["subvol=@var/tmp" "compress=zstd:3" "ssd" "discard=async" "noatime" "x-initrd.mount"];
  };

  # Seagate HDD (sda) - Home, Storage, Var/storage
  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/dffa33dd-4869-4270-8af6-3cedeaf5afee";
    fsType = "btrfs";
    options = ["subvol=@home" "compress=zstd:3" "noatime" "x-initrd.mount"];
  };

  fileSystems."/storage" = {
    device = "/dev/disk/by-uuid/dffa33dd-4869-4270-8af6-3cedeaf5afee";
    fsType = "btrfs";
    options = ["subvol=@" "compress=zstd:3" "noatime" "x-initrd.mount"];
  };

  fileSystems."/var/storage" = {
    device = "/dev/disk/by-uuid/dffa33dd-4869-4270-8af6-3cedeaf5afee";
    fsType = "btrfs";
    options = ["subvol=@var" "compress=zstd:3" "noatime" "x-initrd.mount"];
  };

  # Boot partition (Micron SSD)
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/CD7B-DFCA";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  # Swap partition
  swapDevices = [
    {
      device = "/dev/disk/by-uuid/4471d02c-41c0-4c95-ab04-c9a1e531a120";
    }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}