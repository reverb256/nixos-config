{ config, pkgs, lib, ... }:
let
  params = import ./params.nix;
  inherit (params) pci network raid;
in {
  # No auto-discovery of modules - hypervisor is headless
  # Don't import hardware-configuration.nix (it brings in desktop modules)
  
  nixpkgs.hostPlatform = "x86_64-linux";
  
  # ── File Systems (from hardware-configuration.nix) ─
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
  
  # ── Boot ─
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "amd_iommu=on" "iommu=pt" "kvm.ignore_msrs=1" "pcie_acs_override=downstream"
    # Pass BOTH USB controllers as vfio-pci devices so EVERY port auto-passthroughs
    # to the VM (keyboard, mouse, gamepad, hub — any device, any port, hotplug too).
    #   - Onboard XHCI (0000:0a:00.3, 1022:149c, IOMMU group 20 — alone, no NIC)
    #   - Chipset XHCI (0000:02:00.0, 1022:43ee, group 15 — shares 2 Intel NICs
    #     06:00.0/07:00.0). The NICs also bind to VFIO and are passed to the VM
    #     unused (acceptable on a dedicated gaming host; the VM uses macvtap/bridges
    #     on other interfaces). Whole-controller pass avoids the per-device
    #     startupPolicy='optional' trap where a device not present at VM start is
    #     silently skipped.
    "vfio-pci.ids=${pci.gpu.vendor}:${pci.gpu.device},${pci.gpuAudio.vendor}:${pci.gpuAudio.device},1022:149c,1022:43ee"
    "vfio-pci.disable_idle_d3=1"
    "video=efifb:off" "console=ttyS0,115200"
  ];
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usbhid" "uas" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ "nvme" "btrfs" "vfio" "vfio_iommu_type1" "virtio_pci" "virtio_blk" "md_mod" "raid0" "vfio_pci" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.blacklistedKernelModules = [ "nvidia" "nvidia_drm" "nvidia_modeset" "nvidia_uvm" ];

  # ── VFIO module parameters ─
  boot.extraModprobeConfig = "options vfio-pci disable_idle_d3=1;";

  # ── GPU ─
  # GPU drivers needed for VFIO passthrough to Windows VM
  hardware.nvidia.open = false;
  hardware.nvidia.modesetting.enable = true;
  hardware.graphics.enable = true;
  nixpkgs.config.allowUnfree = true;
  
  # ── Serial console ─
  systemd.services."serial-getty@ttyS0".enable = true;

  # ── RAID assembly ─
  systemd.services.assemble-games-raid = {
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.mdadm pkgs.util-linux ];
    script = ''
      offset=$(( ${toString raid.offset} * 512 ))
      # Find free loop devices instead of hardcoding /dev/loop10/11
      # (those nodes don't exist on NixOS -> losetup fails silently -> mdadm
      # gets no devices -> "no raid-devices specified" -> array never comes up)
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
      # Ensure partition device node exists before dependent services (iscsi-target) start.
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