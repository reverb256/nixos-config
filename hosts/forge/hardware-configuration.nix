{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd = {
      availableKernelModules = ["xhci_pci" "ahci" "sd_mod" "usb_storage" "btrfs"];
      kernelModules = [];
    };
    kernelModules = ["kvm-intel" "amdgpu"];
    extraModulePackages = [];
  };

  # Minimal: disko declares all fileSystems and swapDevices.
  # This file only provides hardware detection (USB, SATA, BTRFS)
  # and boot configuration that disko doesn't cover.

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
