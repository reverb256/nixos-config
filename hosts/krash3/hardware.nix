{ config, pkgs, lib, ... }:
let
  params = import ./params.nix;
  inherit (params) pci network raid;
in {
  nixpkgs.hostPlatform = "x86_64-linux";

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/9659a7e5-54fb-4228-afc3-96244c2612e5";
    fsType = "btrfs";
    options = [ "subvol=/" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/64DA-689B";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  swapDevices = [ ];

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "amd_iommu=on" "iommu=pt" "kvm.ignore_msrs=1" "pcie_acs_override=downstream"
    # VFIO bind list:
    #   - GPU (10de:2882) + GPU audio (10de:22be) for passthrough to krash3-vm.
    #   - ONBOARD Matisse XHCI (1022:149c, 0000:0a:00.3, IOMMU group 20 — alone)
    #     so the WHOLE controller passes to the VM: every onboard port, hubs,
    #     and hotplugged devices appear in Windows automatically. Group 20 is
    #     isolated -> viable, so this works.
    #   - The CHIPSET XHCI (1022:43ee, 0000:02:00.0, group 15) is DELIBERATELY
    #     ABSENT: it shares its IOMMU group with the host Intel NIC/SATA/WiFi,
    #     so it can never be made viable ("group 15 is not viable" aborts the
    #     VM). Chipset-port devices are covered by per-device USB passthrough in
    #     declarative-vm.nix. Never add 1022:43ee back here.
    "vfio-pci.ids=${pci.gpu.vendor}:${pci.gpu.device},${pci.gpuAudio.vendor}:${pci.gpuAudio.device},1022:149c"
    "vfio-pci.disable_idle_d3=1"
    "video=efifb:off" "console=ttyS0,115200"
  ];
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usbhid" "uas" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ "nvme" "btrfs" "vfio" "vfio_iommu_type1" "virtio_pci" "virtio_blk" "md_mod" "raid0" "vfio_pci" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.blacklistedKernelModules = [ "nvidia" "nvidia_drm" "nvidia_modeset" "nvidia_uvm" ];

  boot.extraModprobeConfig = "options vfio-pci disable_idle_d3=1;";

  hardware.nvidia.open = false;
  hardware.nvidia.modesetting.enable = true;
  hardware.graphics.enable = true;
  nixpkgs.config.allowUnfree = true;

  systemd.services."serial-getty@ttyS0".enable = true;

  systemd.services.assemble-games-raid = {
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.mdadm pkgs.util-linux ];
    script = ''
      offset=$(( ${toString raid.offset} * 512 ))
      dev0=$(losetup -f --show -o $offset ${builtins.elemAt raid.devices 0} 2>/dev/null || true)
      dev1=$(losetup -f --show -o $offset ${builtins.elemAt raid.devices 1} 2>/dev/null || true)
      if [ -z "$dev0" ] || [ -z "$dev1" ]; then
        echo "ERROR: could not set up loop devices for RAID (dev0='$dev0' dev1='$dev1')"
        exit 1
      fi
      echo "RAID loop devices: $dev0 $dev1"
      mdadm --build /dev/md0 --level=raid0 --chunk=${toString raid.chunk} \
        --raid-devices=2 "$dev0" "$dev1" 2>/dev/null || true
      if [ ! -b /dev/md0p1 ]; then
        printf "label: gpt\nstart=32768, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7\n" | sfdisk --wipe never /dev/md0 2>/dev/null || true
      fi
      /run/current-system/sw/bin/partx -a /dev/md0 2>/dev/null || true
      /run/current-system/sw/bin/udevadm settle 2>/dev/null || true
      for i in $(seq 1 10); do
        if [ -b /dev/md0p1 ]; then break; fi
        sleep 1
      done
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };
}
