{ config, pkgs, lib, ... }:
let
  params = import ./params.nix;
  inherit (params) pci network raid;
in {
  # Pin the host CPU governor to performance so the pinned guest vCPUs in
  # krash3-vm never get clock-gated between frames (powersave/amd-pstate-epp
  # caused periodic micro-stutter in the Windows gaming guest).
  powerManagement.cpuFreqGovernor = "performance";

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
    systemd-boot = {
      enable = true;
      # NixOS-managed systemd-boot rewrites /boot/loader/loader.conf on every
      # `nixos-rebuild switch` and defaults to the newest generation, so no
      # manual override is needed. The previous `defaultEntry = "NixOS"`
      # (commit 2d1967c0) was a no-op (option removed upstream) and later
      # attempts to use `entryDefault` (also removed) both blocked
      # evaluation — see commit chain for f37197d5 / f37197d6.
    };
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
    # AMD VFIO stability (prevents 500%+ qemu CPU / reset storms)
    "pcie_aspm=off"
    "kvm_amd.msr_filter=0"
    "isolcpus=1-12"
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

  # Belt-and-suspenders: force the performance governor at boot. The
  # powerManagement.cpuFreqGovernor option is not reliably enforced on
  # linuxPackages_latest (amd-pstate-epp reports powersave by default), so a
  # oneshot writes `performance` to every CPU's scaling_governor early in
  # boot. Prevents the periodic gaming-guest stutter from host power-gating.
  systemd.services.set-cpu-governor = {
    description = "Force performance CPU governor for low-latency VFIO gaming";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance > "$f" 2>/dev/null || true
      done
    '';
  };

  systemd.services.assemble-games-raid = {
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.mdadm pkgs.util-linux pkgs.gawk ];
    script = ''
      # ── Cleanup any stale loop devices from previous boots ──
      # This prevents losetup -f from returning a device that was left
      # dangling after an unclean shutdown, which could cause the new
      # loop to point at a different offset and corrupt the RAID data.
      for dev in /dev/loop*; do
        [ -b "$dev" ] || continue
        backing=$(losetup -nO BACK-FILE "$dev" 2>/dev/null || true)
        case "$backing" in
          /dev/sda|/dev/sdb) losetup -d "$dev" 2>/dev/null || true ;;
        esac
      done

      # ── Set up loop devices at the correct offset ──
      offset=$(( ${toString raid.offset} * 512 ))
      dev0=$(losetup -f --show -o $offset ${builtins.elemAt raid.devices 0})
      dev1=$(losetup -f --show -o $offset ${builtins.elemAt raid.devices 1})
      echo "RAID loop devices: $dev0 $dev1"

      # ── Build md0 only if it doesn't already exist ──
      if [ ! -e /dev/md0 ]; then
        mdadm --build /dev/md0 --level=raid0 --chunk=${toString raid.chunk} \
          --raid-devices=2 "$dev0" "$dev1"
      else
        echo "md0 already exists — skipping rebuild"
      fi

      # ── Verify NTFS integrity ──
      NTFS_SIG=$(dd if=/dev/md0 bs=512 skip=32768 count=1 2>/dev/null | od -A x -t x1z -v | head -1)
      if echo "$NTFS_SIG" | grep -q "eb 52 90 4e 54 46 53"; then
        echo "NTFS signature valid"
      else
        echo "WARNING: NTFS signature MISSING — restoring from backup"
        if [ -f /root/ntfs-boot-backup.img ]; then
          dd if=/root/ntfs-boot-backup.img of=/dev/md0 bs=512 seek=32768 count=16 conv=notrunc 2>/dev/null
          dd if=/root/ntfs-backup-area-backup.img of=/dev/md0 bs=512 seek=$((3904911359 - 15)) count=16 conv=notrunc 2>/dev/null
          echo "NTFS boot sector restored from backup"
        else
          echo "CRITICAL: No NTFS backup available — data may be lost"
        fi
      fi
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };
}
