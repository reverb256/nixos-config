{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usbcore" "usb_storage" "sd_mod" "rtsx_pci_sdmmc"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"];
  boot.extraModulePackages = [];

  fileSystems."/" = {
    device = "/dev/disk/by-label/root";
    fsType = "btrfs";
    options = ["subvol=@" "compress=zstd:3" "ssd" "discard=async" "noatime"];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-label/root";
    fsType = "btrfs";
    options = ["subvol=@home" "compress=zstd:3" "ssd" "discard=async" "noatime"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/EFI";
    fsType = "vfat";
  };

#  swapDevices = [
#    {
#      device = "/dev/disk/by-uuid/e1d0c1f5-3f1b-4c0b-9b9f-7f4a8b9c8d7e";
#    }
#  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;
}
