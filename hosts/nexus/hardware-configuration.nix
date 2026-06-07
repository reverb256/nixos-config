{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  # NVMe0n1 (root btrfs) - Root, Home, Data mounts

  fileSystems."/home" = {
    device = "/dev/disk/by-partlabel/disk-nvme1n1-root";
    fsType = "btrfs";
    options = ["subvol=@home" "ssd" "discard=async" "noatime" "commit=300"];
  };

  fileSystems."/data/hermes" = {
    device = "/dev/disk/by-partlabel/disk-nvme1n1-root";
    fsType = "btrfs";
    options = ["subvol=@home" "ssd" "discard=async" "noatime" "commit=300"];
  };

  fileSystems."/data/models" = {
    device = "/dev/disk/by-partlabel/disk-nvme1n1-root";
    fsType = "btrfs";
    options = ["subvol=@home" "ssd" "discard=async" "noatime" "commit=300"];
  };

  fileSystems."/data/pi" = {
    device = "/dev/disk/by-partlabel/disk-nvme1n1-root";
    fsType = "btrfs";
    options = ["subvol=@home" "ssd" "discard=async" "noatime" "commit=300"];
  };

  # NVMe1n1 (nix btrfs) - Nix, Var
  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/4bd91588-d1ed-4cd9-9cdd-86d515a12cb3";
    fsType = "btrfs";
    options = ["subvol=@nix" "compress=zstd:3" "ssd" "discard=async" "noatime"];
  };

  fileSystems."/var" = {
    device = "/dev/disk/by-uuid/4bd91588-d1ed-4cd9-9cdd-86d515a12cb3";
    fsType = "btrfs";
    options = ["subvol=@var" "compress=zstd:3" "ssd" "discard=async" "noatime"];
  };

  # Boot partition (NVMe0n1)

  # Swap partition
  swapDevices = [
    {
      device = "/dev/disk/by-uuid/5ade035b-22d7-46e0-88d1-cd876d0cbd81";
    }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}