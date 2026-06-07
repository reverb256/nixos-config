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