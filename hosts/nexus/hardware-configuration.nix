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
      availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" "bcache"];
      kernelModules = [];
    };
    kernelModules = ["kvm-amd"];
    extraModulePackages = [];
  };

  # nvme1n1 mount - not managed by disko
  fileSystems."/data/worn" = {
    device = "/dev/disk/by-uuid/2056c7e4-cd6c-4a67-9b3d-001178a70eaa";
    fsType = "btrfs";
    options = ["subvol=@worn" "compress=zstd" "ssd" "discard=async" "nofail" "x-systemd.device-timeout=10s"];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
