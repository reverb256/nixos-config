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
    kernelModules = ["kvm-amd" "amdgpu"];
    extraModulePackages = [];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
