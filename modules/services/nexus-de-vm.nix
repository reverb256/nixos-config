# ─────────────────────────────────────────────────────────────────
# Nexus DE VM — Windows 11 via libvirt/QEMU with dynamic GPU handoff
#
# The RTX 3060 Ti boots on the nvidia driver (no VFIO blacklist).
# A coordinator script:
#   1. Drains host GPU processes (AI inference)
#   2. Unbinds GPU from nvidia → vfio-pci
#   3. Starts the VM
#   4. On stop: unbinds from vfio-pci → rebinds to nvidia
#
# This lets the GPU serve AI inference workloads when the VM is off.
# ─────────────────────────────────────────────────────────────────

{ config, lib, pkgs, ... }:
let
  cfg = config.services.nexus-de-vm;
  inherit (lib) mkEnableOption mkOption types mkIf;

  # GPU PCI addresses on nexus (verified via lspci)
  gpuDevices = [ "0000:0a:00.0" "0000:0a:00.1" ];

  # ── GPU handoff script ────────────────────────────────────────
  # Switches GPU between nvidia (host) and vfio-pci (VM) drivers
  handoffScript = pkgs.writeShellScript "nexus-de-handoff" ''
    set -euo pipefail

    MODE="''${1:-}"  # "pre" (host→VFIO) or "post" (VFIO→host)
    LOG="/var/log/nexus-de-vm-handoff.log"

    log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

    release_gpu_to_host() {
      # Check if vfio-pci has the device
      for dev in ${builtins.toString gpuDevices}; do
        if [ -L /sys/bus/pci/drivers/vfio-pci/"$dev" ]; then
          log "Unbinding $dev from vfio-pci"
          echo "$dev" > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null || true
          echo "" > /sys/bus/pci/devices/"$dev"/driver_override 2>/dev/null || true
        fi
      done

      # Rebind to nvidia
      log "Rebinding to nvidia driver..."
      echo "10de 2486" > /sys/bus/pci/drivers/nvidia/remove_id 2>/dev/null || true
      for dev in ${builtins.toString gpuDevices}; do
        echo "$dev" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null || log "WARN: $dev rebind to nvidia failed (may need nvidia module reload)"
      done

      log "GPU returned to host"
    }

    claim_gpu_for_vm() {
      # Stop host processes using the GPU
      log "Draining host GPU processes..."

      # Stop AI inference services if running
      for svc in llama-server sentry-inference vllm; do
        systemctl stop "$svc" 2>/dev/null || true
      done

      # Wait for nvidia driver to be idle
      if nvidia-smi &>/dev/null; then
        # Try to reset and unload
        nvidia-smi -pm 0 2>/dev/null || true
        sleep 1
      fi

      # Unbind from nvidia
      for dev in ${builtins.toString gpuDevices}; do
        if [ -L /sys/bus/pci/drivers/nvidia/"$dev" ]; then
          log "Unbinding $dev from nvidia"
          echo "$dev" > /sys/bus/pci/drivers/nvidia/unbind 2>/dev/null || true
        fi
      done

      # Bind to vfio-pci
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
        # Re-check for driver modules
        ;;
      *)
        echo "Usage: $0 {pre|post}"
        exit 1
        ;;
    esac
  '';
in {
  options.services.nexus-de-vm = {
    enable = mkEnableOption "Nexus DE Windows 11 VM with dynamic GPU handoff";

    vcpu = mkOption {
      type = types.int;
      default = 8;
      description = "Number of vCPUs for the VM";
    };

    memory = mkOption {
      type = types.str;
      default = "24GiB";
      description = "Memory allocation for the VM (e.g. 24GiB)";
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
    # ── No VFIO boot blacklist — GPU stays on nvidia driver ─────
    # The VFIO binding happens dynamically via the handoff script.
    # IOMMU must still be enabled (see hardware.nix).

    # ── Libvirt ─────────────────────────────────────────────────
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        # ovmf is available by default since nixpkgs removed the submodule
        swtpm.enable = true;
        runAsRoot = true;
      };
    };

    # ── Required packages ───────────────────────────────────────
    environment.systemPackages = with pkgs; [
      libvirt  # virsh
      OVMF     # UEFI firmware
      qemu_kvm # KVM + QEMU
      swtpm    # TPM for Windows 11
    ];

    # ── Kernel modules for VFIO (loaded on demand, not at boot) ─
    boot.kernelModules = [ "vfio" "vfio_pci" "vfio_iommu_type1" ];
    boot.extraModprobeConfig = ''
      options vfio-pci disable_vga=1
    '';

    # ── Libvirt domain definition ───────────────────────────────
    environment.etc."libvirt/qemu/nexus-de.xml" = {
      mode = "0644";
      text = ''
        <domain type='kvm'>
          <name>nexus-de</name>
          <title>Windows 11 — Nexus Desktop Environment</title>
          <description>RTX 3060 Ti VFIO passthrough, 4K TV, USB keyboard/mouse</description>
          <uuid>c0c0a000-0000-4000-8000-000000000001</uuid>
          <memory unit='GiB'>${cfg.memory}</memory>
          <vcpu placement='static'>${toString cfg.vcpu}</vcpu>
          <os>
            <type arch='x86_64' machine='q35'>hvm</type>
            <loader readonly='yes' type='pflash'>${cfg.uefiCode}</loader>
            <nvram template='${cfg.uefiVars}'>/var/lib/libvirt/qemu/nvram/nexus-de_VARS.fd</nvram>
            <boot dev='hd'/>
          </os>
          <features>
            <acpi/>
            <apic/>
            <hyperv>
              <relaxed state='on'/>
              <vapic state='on'/>
              <spinlocks state='on' retries='8191'/>
            </hyperv>
            <kvm>
              <hidden state='on'/>
            </kvm>
            <vmport state='off'/>
            <smm state='on'/>
          </features>
          <cpu mode='host-passthrough' check='none'>
            <topology sockets='1' dies='1' cores='${toString cfg.vcpu}' threads='1'/>
          </cpu>
          <clock offset='localtime'>
            <timer name='hypervclock' present='yes'/>
            <timer name='hpet' present='no'/>
          </clock>
          <devices>
            <!-- GPU VFIO passthrough (10DE:2486 — RTX 3060 Ti) -->
            <hostdev mode='subsystem' type='pci' managed='yes'>
              <source>
                <address domain='0x0000' bus='0x0a' slot='0x00' function='0x0'/>
              </source>
              <rom file='/usr/share/vgabios/vgabios.bin'/>
            </hostdev>
            <!-- GPU Audio (10DE:228b) -->
            <hostdev mode='subsystem' type='pci' managed='yes'>
              <source>
                <address domain='0x0000' bus='0x0a' slot='0x00' function='0x1'/>
              </source>
            </hostdev>
            <!-- USB TV keyboard (1a2c:2124) -->
            <hostdev mode='subsystem' type='usb' managed='yes'>
              <source>
                <vendor id='0x1a2c'/>
                <product id='0x2124'/>
              </source>
            </hostdev>
            <!-- USB TV mouse (1532:008f) -->
            <hostdev mode='subsystem' type='usb' managed='yes'>
              <source>
                <vendor id='0x1532'/>
                <product id='0x008f'/>
              </source>
            </hostdev>
            <!-- Disk -->
            <disk type='file' device='disk'>
              <driver name='qemu' type='qcow2' cache='writeback' io='threads'/>
              <source file='${cfg.diskPath}'/>
              <target dev='sda' bus='sata'/>
              <boot order='1'/>
            </disk>
            <!-- VirtIO drivers for Windows -->
            <disk type='file' device='cdrom'>
              <driver name='qemu' type='raw'/>
              <source file='/var/lib/libvirt/images/virtio-win.iso'/>
              <target dev='sdb' bus='sata'/>
              <readonly/>
            </disk>
            <!-- Network -->
            <interface type='network'>
              <source network='default'/>
              <model type='virtio'/>
            </interface>
            <!-- Input (tablet for cursor sync) -->
            <input type='tablet' bus='virtio'>
              <address type='pci' domain='0x0000' bus='0x00' slot='0x0c' function='0x0'/>
            </input>
            <!-- Display (Spice — for install/debug, not primary) -->
            <graphics type='spice' port='5900' autoport='yes' listen='127.0.0.1'>
              <listen type='address' address='127.0.0.1'/>
            </graphics>
            <!-- Video (basic VGA for boot/install before NVIDIA driver loads) -->
            <video>
              <model type='vga' vram='16384' heads='1' primary='yes'/>
            </video>
            <!-- TPM 2.0 for Windows 11 -->
            <tpm model='tpm-tis'>
              <backend type='emulator' version='2.0'/>
            </tpm>
            <!-- Channel for guest agent -->
            <channel type='spicevmc'>
              <target type='virtio' name='com.redhat.spice.0'/>
            </channel>
            <!-- Memory balloon -->
            <memballoon model='virtio'>
              <stats period='10'/>
            </memballoon>
            <!-- RNG -->
            <rng model='virtio'>
              <backend model='random'>/dev/urandom</backend>
            </rng>
          </devices>
        </domain>
      '';
    };

    # ── Auto-start the VM via systemd ───────────────────────────
    systemd.services.nexus-de-vm = {
      description = "Nexus DE Windows 11 VM (dynamic GPU handoff)";
      after = [ "libvirtd.service" "network.target" ];
      requires = [ "libvirtd.service" ];
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecCondition = "${pkgs.libvirt}/bin/virsh dominfo nexus-de 2>/dev/null || ${pkgs.libvirt}/bin/virsh define /etc/libvirt/qemu/nexus-de.xml";
        ExecStartPre = "${handoffScript} pre";
        ExecStart = "${pkgs.libvirt}/bin/virsh start nexus-de";
        ExecStop = "${pkgs.libvirt}/bin/virsh destroy nexus-de 2>/dev/null || true";
        ExecStopPost = "${handoffScript} post";
        Restart = "no";  # VM lifecycle managed by virsh
        TimeoutStartSec = "infinity";
        TimeoutStopSec = 120;
      };
    };

    # ── Firewall: allow Spice access from local network ─────────
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
      5900  # Spice display
    ];
  };
}
