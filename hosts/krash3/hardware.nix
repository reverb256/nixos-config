{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  # ── Boot ──
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
  boot.loader.grub.enable = lib.mkForce false;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "amd_iommu=on" "iommu=pt" "kvm.ignore_msrs=1" "vfio-pci.ids=10de:2882,10de:22be"
    "video=efifb:off"
    "console=ttyS0,115200"
  ];
  boot.initrd.kernelModules = [ "nvme" "btrfs" "vfio" "vfio_iommu_type1" "virtio_pci" "virtio_blk" "md_mod" "raid0" "vfio_pci" ];
  boot.blacklistedKernelModules = [ "nvidia" "nvidia_drm" "nvidia_modeset" "nvidia_uvm" ];

  # ── GPU ─────────────────────────────────────────────────
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = false;
  hardware.nvidia.modesetting.enable = true;
  hardware.opengl.enable = true;
  nixpkgs.config.allowUnfree = true;

  # ── Serial console ──────────────────────────────────────
  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
  };

  # ── ZRAM ────────────────────────────────────────────────
  zramSwap.enable = true;

  # ── RAID assembly ───────────────────────────────────────
  systemd.services.assemble-games-raid = {
    wantedBy = [ "local-fs.target" ];
    before = [ "local-fs.target" ];
    path = [ pkgs.mdadm pkgs.util-linux ];
    script = ''
      offset=$((1069056 * 512))
      losetup -o $offset /dev/loop10 /dev/sdb 2>/dev/null || true
      losetup -o $offset /dev/loop11 /dev/sda 2>/dev/null || true
      mdadm --build /dev/md0 --level=raid0 --chunk=64 \
        --raid-devices=2 /dev/loop10 /dev/loop11 2>/dev/null || true
      if [ ! -b /dev/md0p1 ]; then
        printf "label: gpt\nstart=32768, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7\n" | sfdisk /dev/md0 2>/dev/null || true
      fi
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };
}
