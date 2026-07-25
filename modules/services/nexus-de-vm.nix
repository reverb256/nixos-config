# ─────────────────────────────────────────────────────────────────
# Nexus DE VM — Windows 11 IoT Enterprise LTSC (GPU-passthrough gaming)
# via libvirt/QEMU with DYNAMIC GPU handoff.
#
# The RTX 3060 Ti boots on the nvidia driver (no permanent VFIO blacklist).
# A coordinator script:
#   1. Drains host GPU processes (AI inference)
#   2. Allocates 2M hugepages for the guest
#   3. Unbinds GPU from nvidia -> vfio-pci
#   4. Starts the VM
#   5. On stop: unbinds vfio-pci -> rebinds nvidia, releases hugepages
#
# Gaming-tuning applied (cutting-edge 2026 baseline):
#   - Single-CCD vCPU pinning (3900X: VM on CCD1 threads 12-23)
#   - Dynamic 2M hugepages (kills TLB misses / stutter)
#   - vendor_id=AuthenticAMD (defeats NVIDIA 0x113 VM-detection crash)
#   - Full Hyper-V enlightenments (hv-time, vpindex, synic, stimer, ...)
#   - memballoon=none (avoids AMD IOMMU / virtio-balloon DMA conflict)
#   - maxphysaddr cap=39 (stops QEMU mapping GPU BARs to rejected IOVAs)
# ─────────────────────────────────────────────────────────────────
{ config, lib, pkgs, ... }:
let
  cfg = config.services.nexus-de-vm;
  inherit (lib) mkEnableOption mkOption types mkIf;

  # GPU PCI addresses on nexus (verified via lspci — IOMMU group 16, isolated)
  gpuDevices = ["0000:0a:00.0" "0000:0a:00.1"];

  # 2M hugepages needed for the guest (memory default 24GiB / 2MiB).
  hugepages2M = let
    gib = let v = builtins.match "([0-9]+)GiB" cfg.memory; in
      if v == null then 24 else builtins.fromJSON (builtins.elemAt v 0);
  in gib * 512;

  # ── GPU handoff + hugepage coordinator script ─────────────────
  handoffScript = pkgs.writeShellScript "nexus-de-handoff" ''
    set -euo pipefail

    MODE="''${1:-}"  # "pre" (host->VFIO) or "post" (VFIO->host)
    LOG="/var/log/nexus-de-vm-handoff.log"

    log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

    HUGE="$(( ${toString hugepages2M} ))"

    alloc_hugepages() {
      log "Allocating $HUGE x 2M hugepages for guest..."
      echo "$HUGE" > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || true
      local got
      got=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || echo 0)
      if [ "$got" -lt "$HUGE" ]; then
        log "WARN: only $got/$HUGE 2M hugepages allocated (host fragmented) — VM may fall back to THP"
      else
        log "Hugepages ready: $got"
      fi
    }

    release_hugepages() {
      log "Releasing 2M hugepages..."
      echo 0 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || true
    }

    release_gpu_to_host() {
      for dev in ${builtins.toString gpuDevices}; do
        if [ -L /sys/bus/pci/drivers/vfio-pci/"$dev" ]; then
          log "Unbinding $dev from vfio-pci"
          echo "$dev" > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null || true
          echo "" > /sys/bus/pci/devices/"$dev"/driver_override 2>/dev/null || true
        fi
      done

      log "Rebinding to nvidia driver..."
      echo "10de 2486" > /sys/bus/pci/drivers/nvidia/remove_id 2>/dev/null || true
      for dev in ${builtins.toString gpuDevices}; do
        echo "$dev" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null || log "WARN: $dev rebind to nvidia failed (may need nvidia module reload)"
      done

      release_hugepages
      log "GPU returned to host"
    }

    claim_gpu_for_vm() {
      alloc_hugepages

      log "Draining host GPU processes..."
      for svc in llama-server sentry-inference vllm; do
        systemctl stop "$svc" 2>/dev/null || true
      done

      if nvidia-smi &>/dev/null; then
        nvidia-smi -pm 0 2>/dev/null || true
        sleep 1
      fi

      for dev in ${builtins.toString gpuDevices}; do
        if [ -L /sys/bus/pci/drivers/nvidia/"$dev" ]; then
          log "Unbinding $dev from nvidia"
          echo "$dev" > /sys/bus/pci/drivers/nvidia/unbind 2>/dev/null || true
        fi
      done

      log "Binding to vfio-pci..."
      modprobe vfio-pci 2>/dev/null || true
      for dev in ${builtins.toString gpuDevices}; do
        echo "vfio-pci" > /sys/bus/pci/devices/"$dev"/driver_override 2>/dev/null || true
        echo "$dev" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || log "WARN: $dev VFIO bind failed (already bound?)"
      done

      log "GPU claimed for VM"
    }

    case "$MODE" in
      pre)
        claim_gpu_for_vm
        ;;
      post)
        release_gpu_to_host
        ;;
      *)
        echo "Usage: $0 {pre|post}"
        exit 1
        ;;
    esac
  '';
in {
  options.services.nexus-de-vm = {
    enable = mkEnableOption "Nexus DE Windows 11 LTSC VM with dynamic GPU handoff";

    vcpu = mkOption {
      type = types.int;
      default = 8;
      description = "Number of vCPUs for the VM (pinned to CCD1 on the 3900X).";
    };

    memory = mkOption {
      type = types.str;
      default = "24GiB";
      description = "Memory allocation for the VM (e.g. 24GiB). Sized in 2M hugepages.";
    };

    diskPath = mkOption {
      type = types.path;
      default = "/var/lib/libvirt/images/nexus-de.qcow2";
      description = "Path to the Windows 11 qcow2 disk image";
    };

    uefiCode = mkOption {
      type = types.path;
      default = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
      description = "Path to UEFI firmware code";
    };

    uefiVars = mkOption {
      type = types.path;
      default = "${pkgs.OVMF.fd}/FV/OVMF_VARS.fd";
      description = "Path to UEFI firmware vars template";
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

    environment.etc."libvirt/qemu/nexus-de.xml" = {
      mode = "0644";
      text = ''
        <domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
          <name>nexus-de</name>
          <title>Windows 11 IoT LTSC — Nexus Gaming VM</title>
          <description>RTX 3060 Ti VFIO passthrough, 4K TV, USB keyboard/mouse. Hardened: CCD1 pinning, hugepages, vendor_id spoof, full Hyper-V enlightenments.</description>
          <uuid>c0c0a000-0000-4000-8000-000000000001</uuid>
          <memory unit='GiB'>${cfg.memory}</memory>
          <vcpu placement='static'>${toString cfg.vcpu}</vcpu>
          <iothreads>1</iothreads>
          <os>
            <type arch='x86_64' machine='q35'>hvm</type>
            <loader readonly='yes' type='pflash'>${cfg.uefiCode}</loader>
            <nvram template='${cfg.uefiVars}'>/var/lib/libvirt/qemu/nvram/nexus-de_VARS.fd</nvram>
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
              <stimer state='on'>
                <direct state='on'/>
              </stimer>
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
          <cputune>
            <vcpupin vcpu='0' cpuset='12'/>
            <vcpupin vcpu='1' cpuset='13'/>
            <vcpupin vcpu='2' cpuset='14'/>
            <vcpupin vcpu='3' cpuset='15'/>
            <vcpupin vcpu='4' cpuset='16'/>
            <vcpupin vcpu='5' cpuset='17'/>
            <vcpupin vcpu='6' cpuset='18'/>
            <vcpupin vcpu='7' cpuset='19'/>
            <emulatorpin cpuset='0-1'/>
            <iothreadpin iothread='1' cpuset='0-1'/>
          </cputune>
          <memoryBacking>
            <hugepages>
              <page size='2048' unit='KiB'/>
            </hugepages>
            <nocache/>
          </memoryBacking>
          <devices>
            <hostdev mode='subsystem' type='pci' managed='yes'>
              <source>
                <address domain='0x0000' bus='0x0a' slot='0x00' function='0x0'/>
              </source>
              <rom file='/usr/share/vgabios/vgabios.bin'/>
            </hostdev>
            <hostdev mode='subsystem' type='pci' managed='yes'>
              <source>
                <address domain='0x0000' bus='0x0a' slot='0x00' function='0x1'/>
              </source>
            </hostdev>
            <hostdev mode='subsystem' type='usb' managed='yes'>
              <source>
                <vendor id='0x1a2c'/>
                <product id='0x2124'/>
              </source>
            </hostdev>
            <hostdev mode='subsystem' type='usb' managed='yes'>
              <source>
                <vendor id='0x1532'/>
                <product id='0x008f'/>
              </source>
            </hostdev>
            <disk type='file' device='disk'>
              <driver name='qemu' type='qcow2' cache='writeback' io='threads' iothread='1'/>
              <source file='${cfg.diskPath}'/>
              <target dev='sda' bus='sata'/>
              <boot order='1'/>
            </disk>
            <disk type='file' device='cdrom'>
              <driver name='qemu' type='raw'/>
              <source file='/var/lib/libvirt/images/virtio-win.iso'/>
              <target dev='sdb' bus='sata'/>
              <readonly/>
            </disk>
            <interface type='network'>
              <source network='default'/>
              <model type='virtio'/>
            </interface>
            <input type='tablet' bus='virtio'>
              <address type='pci' domain='0x0000' bus='0x00' slot='0x0c' function='0x0'/>
            </input>
            <graphics type='spice' port='5900' autoport='yes' listen='127.0.0.1'>
              <listen type='address' address='127.0.0.1'/>
            </graphics>
            <video>
              <model type='vga' vram='16384' heads='1' primary='yes'/>
            </video>
            <tpm model='tpm-tis'>
              <backend type='emulator' version='2.0'/>
            </tpm>
            <channel type='spicevmc'>
              <target type='virtio' name='com.redhat.spice.0'/>
            </channel>
            <memballoon model='none'/>
            <rng model='virtio'>
              <backend model='random'>/dev/urandom</backend>
            </rng>
          </devices>
        </domain>
      '';
    };

    systemd.services.nexus-de-vm = {
      description = "Nexus DE Windows 11 LTSC VM (dynamic GPU handoff)";
      after = ["libvirtd.service" "network.target"];
      requires = ["libvirtd.service"];
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecCondition = "${pkgs.libvirt}/bin/virsh dominfo nexus-de 2>/dev/null || ${pkgs.libvirt}/bin/virsh define /etc/libvirt/qemu/nexus-de.xml";
        ExecStartPre = "${handoffScript} pre";
        ExecStart = "${pkgs.libvirt}/bin/virsh start nexus-de";
        ExecStop = "${pkgs.libvirt}/bin/virsh destroy nexus-de 2>/dev/null || true";
        ExecStopPost = "${handoffScript} post";
        Restart = "no";
        TimeoutStartSec = "infinity";
        TimeoutStopSec = 120;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
      5900
    ];
  };
}
