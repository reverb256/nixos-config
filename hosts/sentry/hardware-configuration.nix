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
      availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "sd_mod" "bcache"];
      kernelModules = [];
    };
    kernelModules = ["kvm-amd"];
    extraModulePackages = [];
  };

  # Note: fileSystems for "/", "/home", "/boot", "/nix", "/persistent" are managed by disko.nix
  # /storage mount is handled by disko nodev (preserves existing data)

  # Use existing swap partition on SSD (sdb2)
  swapDevices = [
    {device = "/dev/disk/by-uuid/b708afe1-3cde-43e1-a047-03b5a1c1c5ac";}
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
