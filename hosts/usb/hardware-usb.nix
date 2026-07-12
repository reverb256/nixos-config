# Generic hardware config for USB rescue ISO
# Designed to boot on ANY x86_64 machine — not host-specific
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Broad kernel module support for any hardware
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ehci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "sd_mod"
    "uas"
    "usbhid"
    "rtsx_pci_sdmmc"
    "nvme_core"
    "virtio_blk"
    "virtio_net"
    "virtio_pci"
  ];

  # GPU kernel modules loaded after rootfs is mounted (not in initrd, so they
  # don	 block builds on kernels that don't ship every module)
  boot.initrd.kernelModules = [
    "amdgpu"
    "i915"
  ];

  boot.kernelModules = [
    "amdgpu"
    "nvidia"
    "nvidia_modeset"
    "nvidia_drm"
    "nvidia_uvm"
    "i915"
    "e1000e"
    "r8169"
    "igb"
  ];

  # Load all common GPU drivers — works on any host in the cluster
  services.xserver.videoDrivers = ["amdgpu" "nvidia" "modesetting"];

  # nvidia module requires an explicit open/closed choice on driver >= 560
  # (null triggers a type error in nixpkgs' nvidia.nix assertion). Closed-source
  # modules give the widest GPU compatibility for a generic rescue ISO.
  hardware.nvidia.open = false;

  hardware.enableRedistributableFirmware = true;

  # USB boot support
  boot.supportedFilesystems = ["btrfs" "ext4" "vfat" "exfat" "ntfs" "tmpfs"];
}
