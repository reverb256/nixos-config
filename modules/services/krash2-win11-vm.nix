# ─────────────────────────────────────────────────────────────────
# krash2-win11 — migrate the krash2 physical box into a VM on nexus
# via libvirt/QEMU/KVM. Physical disk passthrough keeps the install intact.
#
# Strategy (P2V-by-passthrough):
#   Move krash2's two SATA drives into nexus (6 free SATA ports):
#     - SanDisk 960GB SSD  (C:, Windows 10 install)  → /dev/disk/by-id/ata-SanDisk_SSD_960GB_*
#     - WD 2TB HDD         (D:, data)                → /dev/disk/by-id/ata-WDC_WD20EZBX-00AYRA0_*
#   Attach them as SATA block passthrough. Windows boots its OWN unmodified
#   OS image — the existing AHCI boot driver works, no virtio injection,
#   no disk conversion, no reactivation from a hardware fingerprint change
#   beyond what Win10 already tolerates.
#
# No GPU passthrough yet (the RTX 4060 stays in the krash2 chassis; its fate
# is a separate decision). This VM is headless: install/operate via serial
# console or RDP once the guest network is up.
#
# Preflight: SVM must be enabled in nexus BIOS (M.I.T. → Advanced Frequency
# Settings → Advanced CPU Core Settings → SVM Mode → Enabled), else /dev/kvm
# is absent and KVM acceleration is impossible.
#
# ── OPERATOR CHECKLIST (before and during the move) ──────────────────────
# Before the move (krash2 still running):
#   1. Back up critical data (D:\Backup\2026-06-18 exists; refresh it).
#   2. Stage virtio-win drivers on krash2 (install the virtio-win ISO /
#      guest tools). This registers viostor + NetKVM as available drivers so
#      the VM can later switch off SATA/e1000e without a driver hunt.
#      Optional but recommended — SATA passthrough already boots with the
#      inbox AHCI driver.
#   3. Note the Windows product key (slmgr /dli or registry) — reactivation
#      WILL be needed after the move (see below).
#   4. If the license is a digital license, link it to the Microsoft account
#      to improve reactivation odds.
# Physical move:
#   5. Shut down krash2 cleanly. Pull both SATA drives. Note which SATA port
#      each was on (C: = boot disk).
#   6. Install into nexus's free SATA slots. Verify the by-id paths below
#      with: ls -l /dev/disk/by-id/ | grep -E "ata-(SanDisk|WDC)"
#      NEVER mount the drives on the host — the VM owns them raw.
#   7. Update bootDisk/dataDisk below to the ACTUAL serials.
#   8. Enable SVM in nexus BIOS. Set services.krash2-win11-vm.enable = true.
#      Deploy.
# First boot in the VM:
#   9. Boot with SATA passthrough + e1000e NIC (inbox drivers). Expect a long
#      first boot (hardware detection).
#  10. Windows WILL report not-activated: the Win10 Pro OEM license is tied
#      to the old hardware and cannot transfer to a VM. Run the Activation
#      Troubleshooter (only works if the license is a digital license linked
#      to a Microsoft account), enter the original product key (retail only),
#      or use the staged LTSC ISO as the new license path (KMS/MAK).
#  11. Install NetKVM + virtio drivers from the mounted virtio-win ISO.
#      Optionally switch the NIC to virtio, then the disk bus to virtio
#      (only after drivers are registered as boot-critical).
# ──────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.krash2-win11-vm;
  inherit (lib) mkEnableOption mkOption types mkIf;

  # krash2 drives — fill in the actual serials after the physical move.
  # These by-id paths must exist on nexus once the drives are installed.
  # Use `ls -l /dev/disk/by-id/ | grep -E "ata-(SanDisk|WDC)"` to confirm.
  bootDisk = "/dev/disk/by-id/ata-SanDisk_SSD_960GB_152314406172";
  dataDisk = "/dev/disk/by-id/ata-WDC_WD20EZBX-00AYRA0_WD-WXT2AC0N1R72";

  # LTSC ISO staged at /data/backups/iso (verified SHA-256 f6b14814 official)
  isoPath = "/data/backups/iso/en-us_windows_11_iot_enterprise_ltsc_2024_x64_dvd_f6b14814.iso";

  domainXml = ''
    <domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
      <name>krash2-win11</name>
      <title>krash2 migrated Windows 10 VM</title>
      <description>Physical-to-virtual migration of the krash2 box (10.1.1.79). Physical SATA disk passthrough keeps the install intact.</description>
      <memory unit='GiB'>${cfg.memory}</memory>
      <vcpu placement='static'>${toString cfg.vcpu}</vcpu>
      <os>
        <type arch='x86_64' machine='q35'>hvm</type>
        <loader readonly='yes' type='pflash'>${pkgs.OVMF.fd}/FV/OVMF_CODE.fd</loader>
        <nvram template='${pkgs.OVMF.fd}/FV/OVMF_VARS.fd'>/var/lib/libvirt/qemu/nvram/krash2-win11_VARS.fd</nvram>
        <boot dev='hd'/>
      </os>
      <features>
        <acpi/>
        <apic/>
        <hyperv mode='custom'>
          <relaxed state='on'/>
          <vapic state='on'/>
          <spinlocks state='on' retries='8191'/>
          <vpindex state='on'/>
          <runtime state='on'/>
          <synic state='on'/>
          <stimer state='on'/>
          <reset state='on'/>
          <frequencies state='on'/>
          <reenlightenment state='on'/>
          <tlbflush state='on'/>
          <ipi state='on'/>
          <vendor_id state='on' value='AuthenticAMD'/>
        </hyperv>
        <kvm>
          <hidden state='on'/>
        </kvm>
        <vmport state='off'/>
        <smm state='on'/>
      </features>
      <cpu mode='host-passthrough' check='none' migratable='off'>
        <topology sockets='1' dies='1' cores='${toString cfg.vcpu}' threads='1'/>
        <cache mode='passthrough'/>
        <maxphysaddr mode='passthrough' limit='39'/>
      </cpu>
      <clock offset='localtime'>
        <timer name='hypervclock' present='yes'/>
        <timer name='hpet' present='no'/>
        <timer name='rtc' tickpolicy='catchup'/>
        <timer name='pit' tickpolicy='delay'/>
      </clock>
      <devices>
        <emulator>${pkgs.qemu_kvm}/bin/qemu-system-x86_64</emulator>
        <!-- C: — krash2's Windows 10 SSD, SATA passthrough (unmodified AHCI boot) -->
        <disk type='block' device='disk'>
          <driver name='qemu' type='raw' cache='writeback'/>
          <source dev='${bootDisk}'/>
          <target dev='sda' bus='sata'/>
          <boot order='1'/>
        </disk>
        <!-- D: — krash2's data HDD, SATA passthrough -->
        <disk type='block' device='disk'>
          <driver name='qemu' type='raw' cache='writeback'/>
          <source dev='${dataDisk}'/>
          <target dev='sdb' bus='sata'/>
        </disk>
        <!-- LTSC ISO as repair/reinstall fallback -->
        <disk type='file' device='cdrom'>
          <driver name='qemu' type='raw'/>
          <source file='${isoPath}'/>
          <target dev='sdc' bus='sata'/>
          <readonly/>
        </disk>
        <controller type='usb' index='0' model='qemu-xhci' ports='15'/>
        <controller type='pci' index='0' model='pcie-root'/>
        <!-- e1000e NIC for FIRST BOOT: Windows 10 ships an inbox e1000e
             driver but NO inbox virtio-net driver. A virtio NIC on first
             boot = no network until NetKVM is installed from a mounted ISO.
             Boot with e1000e (instant network), then install NetKVM from
             virtio-win, then switch this to virtio for performance. -->
        <interface type='network'>
          <source network='default'/>
          <model type='e1000e'/>
        </interface>
        <serial type='pty'>
          <target port='0'/>
        </serial>
        <console type='pty'>
          <target type='serial' port='0'/>
        </console>
        <input type='mouse' bus='virtio'/>
        <input type='keyboard' bus='virtio'/>
        <tpm model='tpm-tis'>
          <backend type='emulator' version='2.0'/>
        </tpm>
        <memballoon model='none'/>
        <rng model='virtio'>
          <backend model='random'>/dev/urandom</backend>
        </rng>
      </devices>
    </domain>
  '';

  # Preflight: refuse to define/start the VM if the passthrough disks
  # aren't present (i.e. the physical move hasn't happened).
  diskCheck = pkgs.writeShellScript "krash2-win11-diskcheck" ''
    set -euo pipefail
    for d in "${bootDisk}" "${dataDisk}"; do
      if [ ! -e "$d" ]; then
        echo "MISSING passthrough disk: $d" >&2
        echo "Move the krash2 drives into nexus first (they attach as by-id)." >&2
        exit 1
      fi
    done
    echo "krash2 passthrough disks present."
  '';
in {
  options.services.krash2-win11-vm = {
    enable = mkEnableOption "krash2 Windows 10 migration VM (physical disk passthrough)";
    vcpu = mkOption {
      type = types.int;
      default = 4;
      description = "vCPU count (thread parity with the i5-2400).";
    };
    memory = mkOption {
      type = types.str;
      default = "16GiB";
      description = "Memory for the VM.";
    };
    bootDisk = mkOption {
      type = types.path;
      default = bootDisk;
      description = "by-id path to krash2's C: SSD.";
    };
    dataDisk = mkOption {
      type = types.path;
      default = dataDisk;
      description = "by-id path to krash2's D: HDD.";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
        runAsRoot = true;
      };
    };

    environment.systemPackages = with pkgs; [
      libvirt
      OVMF
      qemu_kvm
      swtpm
    ];

    environment.etc."libvirt/qemu/krash2-win11.xml" = {
      mode = "0644";
      text = domainXml;
    };

    users.users.j_kro.extraGroups = ["libvirtd" "kvm"];

    systemd.services.krash2-win11-vm = {
      description = "krash2 Windows 10 migration VM (physical disk passthrough)";
      after = ["libvirtd.service" "network.target"];
      requires = ["libvirtd.service"];
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecCondition = "${pkgs.libvirt}/bin/virsh dominfo krash2-win11 2>/dev/null || ${pkgs.libvirt}/bin/virsh define /etc/libvirt/qemu/krash2-win11.xml";
        ExecStartPre = "${diskCheck}";
        ExecStart = "${pkgs.libvirt}/bin/virsh start krash2-win11";
        ExecStop = "${pkgs.libvirt}/bin/virsh destroy krash2-win11 2>/dev/null || true";
        Restart = "no";
        TimeoutStartSec = "infinity";
        TimeoutStopSec = 120;
      };
    };

    # RDP/management access to the guest once installed; console via serial.
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
      3389
    ];
  };
}
