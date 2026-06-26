{ config, pkgs, lib, ... }:
let
  params = import ./params.nix;
  inherit (params) pci network raid;
in {
  imports = [ ./hardware-configuration.nix ];

  # ── Boot ──
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "amd_iommu=on" "iommu=pt" "kvm.ignore_msrs=1" "pcie_acs_override=downstream"
    "vfio-pci.ids=${pci.gpu.vendor}:${pci.gpu.device},${pci.gpuAudio.vendor}:${pci.gpuAudio.device},${pci.usb.vendor}:${pci.usb.device}"
    "video=efifb:off" "console=ttyS0,115200"
  ];
  boot.initrd.kernelModules = [ "nvme" "btrfs" "vfio" "vfio_iommu_type1" "virtio_pci" "virtio_blk" "md_mod" "raid0" "vfio_pci" ];
  boot.blacklistedKernelModules = [ "nvidia" "nvidia_drm" "nvidia_modeset" "nvidia_uvm" ];

  # ── GPU ──
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = false;
  hardware.nvidia.modesetting.enable = true;
  hardware.graphics.enable = true;
  nixpkgs.config.allowUnfree = true;

  # ── Serial console ──
  systemd.services."serial-getty@ttyS0".enable = true;


  # ── RAID assembly ──
  systemd.services.assemble-games-raid = {
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.mdadm pkgs.util-linux ];
    script = ''
      offset=$(( ${toString raid.offset} * 512 ))
      losetup -o $offset /dev/loop10 ${builtins.elemAt raid.devices 0} 2>/dev/null || true
      losetup -o $offset /dev/loop11 ${builtins.elemAt raid.devices 1} 2>/dev/null || true
      mdadm --build /dev/md0 --level=raid0 --chunk=${toString raid.chunk} \
        --raid-devices=2 /dev/loop10 /dev/loop11 2>/dev/null || true
      if [ ! -b /dev/md0p1 ]; then
        printf "label: gpt\nstart=32768, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7\n" | sfdisk --wipe no /dev/md0 2>/dev/null || true
      fi
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };
}
