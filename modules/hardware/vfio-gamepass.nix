# Game Pass Windows VM via VFIO GPU passthrough — zephyr only
#
# Passes the RTX 3060 Ti (IOMMU group 24: 0000:24:00.0 VGA + 0000:24:00.1 audio)
# to a Windows 11 VM. The RTX 3090 stays on the Niri host. Display + input are
# provided by Looking Glass (kvmfr shared-memory bridge). Audio is carried by
# Scream (UDP) — install the Scream sender in the VM; the receiver runs here.
#
# Packages (kvmfr, looking-glass-client, OVMFFull, qemu_kvm, scream, virtio-win)
# come from a RECENT nixpkgs (inputs.nixpkgs-vfio) because the pinned main
# nixpkgs predates their inclusion. kvmfr is rebuilt against the CachyOS kernel.
#
# This module wires the HOST only. You install Windows yourself into
# /var/lib/libvirt/images/gamepass-win11.qcow2 (see bottom note). The domain
# XML is declared and `virsh define`d idempotently on boot.
#
# CPU pinning: Ryzen 5950X has 2 CCDs. VM vCPUs -> CCD1 (host cores 8-15);
# emulator + IO threads -> CCD0 (0-7) so the VM never competes with the host.

{ config, lib, pkgs, vfioPkgs, ... }:

let
  # Passed-through card — IOMMU group 24, isolated (verified via /sys)
  vfioIds = [ "10de:2486" "10de:228b" ]; # RTX 3060 Ti VGA + HDMI audio

  # Domain XML, templated so OVMF / emulator / VirtIO-ISO paths resolve to the store.
  winXml = ''
    <domain xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0" type="kvm">
      <name>gamepass-win11</name>
      <memory unit="KiB">16777216</memory>
      <currentMemory unit="KiB">16777216</currentMemory>
      <vcpu placement="static">8</vcpu>
      <iothreads>2</iothreads>
      <cputune>
        <vcpupin vcpu="0" cpuset="8"/>
        <vcpupin vcpu="1" cpuset="9"/>
        <vcpupin vcpu="2" cpuset="10"/>
        <vcpupin vcpu="3" cpuset="11"/>
        <vcpupin vcpu="4" cpuset="12"/>
        <vcpupin vcpu="5" cpuset="13"/>
        <vcpupin vcpu="6" cpuset="14"/>
        <vcpupin vcpu="7" cpuset="15"/>
        <emulatorpin cpuset="0-7"/>
        <iothreadpin iothread="1" cpuset="0-3"/>
        <iothreadpin iothread="2" cpuset="4-7"/>
      </cputune>
      <os firmware="efi">
        <type arch="x86_64" machine="pc-q35-9.2">hvm</type>
        <boot dev="hd"/>
      </os>
      <features>
        <acpi/>
        <apic/>
        <hyperv mode="custom">
          <relaxed state="on"/>
          <vapic state="on"/>
          <spinlocks state="on" retries="8191"/>
          <vpindex state="on"/>
          <runtime state="on"/>
          <synic state="on"/>
          <stimer state="on"/>
          <frequencies state="on"/>
          <tlbflush state="on"/>
          <ipi state="on"/>
          <evmcs state="off"/>
          <vendor_id state="on" value="1234567890ab"/>
        </hyperv>
        <vmport state="off"/>
      </features>
      <cpu mode="host-passthrough" check="none" migratable="on">
        <topology sockets="1" dies="1" cores="4" threads="2"/>
        <cache mode="passthrough"/>
        <feature policy="require" name="topoext"/>
      </cpu>
      <kvm>
        <hidden state="on"/>
      </kvm>
      <clock offset="localtime">
        <timer name="rtc" tickpolicy="catchup" track="guest"/>
        <timer name="pit" tickpolicy="delay"/>
        <timer name="hpet" present="no"/>
        <timer name="hypervclock" present="yes"/>
      </clock>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>destroy</on_crash>
      <pm>
        <suspend-to-mem enabled="no"/>
        <suspend-to-disk enabled="no"/>
      </pm>
      <devices>
        <emulator>/run/libvirt/nix-emulators/qemu-system-x86_64</emulator>
        <disk type="file" device="disk">
          <driver name="qemu" type="qcow2" cache="none" io="io_uring" discard="unmap"/>
          <source file="/var/lib/libvirt/images/gamepass-win11.qcow2"/>
          <target dev="vda" bus="virtio"/>
        </disk>
        <disk type="file" device="cdrom">
          <driver name="qemu" type="raw"/>
          <source file="${vfioPkgs.virtio-win}/virtio-win.iso"/>
          <target dev="sdb" bus="sata"/>
        </disk>
        <!-- Windows 11 installer ISO. Place your ISO at this path before first boot:
             sudo cp /path/to/Win11.iso /var/lib/libvirt/images/win11.iso -->
        <disk type="file" device="cdrom">
          <driver name="qemu" type="raw"/>
          <source file="/var/lib/libvirt/images/win11.iso"/>
          <target dev="sdc" bus="sata"/>
        </disk>
        <controller type="usb" index="0" model="qemu-xhci" ports="15"/>
        <controller type="pci" index="0" model="pcie-root"/>
        <interface type="network">
          <source network="default"/>
          <model type="virtio"/>
        </interface>
        <serial type="pty"/>
        <console type="pty"/>
        <input type="mouse" bus="virtio"/>
        <input type="keyboard" bus="virtio"/>
        <graphics type="spice" autoport="yes" listen="127.0.0.1">
          <listen type="address" address="127.0.0.1"/>
          <image compression="off"/>
        </graphics>
        <sound model="ich9">
          <audio id="1"/>
        </sound>
        <audio id="1" type="spice"/>
        <video>
          <model type="vga" vram="16384" heads="1" primary="yes"/>
        </video>
        <!-- RTX 3060 Ti (IOMMU group 24) -->
        <hostdev mode="subsystem" type="pci" managed="yes">
          <driver name="vfio"/>
          <source>
            <address domain="0x0000" bus="0x24" slot="0x00" function="0x0"/>
          </source>
          <address type="pci" domain="0x0000" bus="0x05" slot="0x00" function="0x0"/>
        </hostdev>
        <hostdev mode="subsystem" type="pci" managed="yes">
          <driver name="vfio"/>
          <source>
            <address domain="0x0000" bus="0x24" slot="0x00" function="0x1"/>
          </source>
          <address type="pci" domain="0x0000" bus="0x06" slot="0x00" function="0x0"/>
        </hostdev>
        <redirdev bus="usb" type="spicevmc"/>
        <watchdog model="itco" action="reset"/>
        <memballoon model="none"/>
      </devices>
      <qemu:commandline>
        <qemu:arg value="-device"/>
        <qemu:arg value="{'driver':'ivshmem-plain','id':'shmem0','memdev':'looking-glass'}"/>
        <qemu:arg value="-object"/>
        <qemu:arg value="{'qom-type':'memory-backend-file','id':'looking-glass','mem-path':'/dev/kvmfr0','size':67108864,'share':true}"/>
      </qemu:commandline>
    </domain>
  '';
in {
  # Zephyr only. On nexus/forge/sentry this module is a no-op (and must not
  # bind vfio-pci.ids, which would steal their GPUs).
  config = lib.mkIf (config.networking.hostName == "zephyr") {
    # 1. Early VFIO binding BEFORE the nvidia driver claims the 3060 Ti.
    boot.initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
    boot.kernelParams = [
      "kvmfr.static_size_mb=64"
    ];

    # 2. Looking Glass shared memory (kvmfr) — built against the CachyOS kernel.
    # Build kvmfr for the ACTIVE kernel (CachyOS) via linuxPackagesFor — NOT the
    # recent nixpkgs' default kernel. linuxPackages.kvmfr.override { kernel } does
    # not propagate; linuxPackagesFor is the correct constructor.
    boot.extraModulePackages = [
      (vfioPkgs.linuxPackagesFor config.boot.kernelPackages.kernel).kvmfr
    ];
    services.udev.packages = lib.singleton (pkgs.writeTextFile {
      name = "kvmfr-udev";
      text = ''SUBSYSTEM=="kvmfr", GROUP="kvm", MODE="0660", TAG+="uaccess"'';
      destination = "/etc/udev/rules.d/70-kvmfr.rules";
    });

    # 3. libvirt + swtpm (qemu from recent nixpkgs for newer machine types)
    # OVMF is bundled with qemu_kvm by default in current nixpkgs (the
    # `qemu.ovmf` submodule was removed); libvirt auto-selects it via
    # <os firmware="efi"> in the domain XML.
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = vfioPkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
        verbatimConfig = ''
          namespaces = []
          cgroup_device_acl = [
            "/dev/null", "/dev/full", "/dev/zero", "/dev/random", "/dev/urandom",
            "/dev/ptmx", "/dev/kvm", "/dev/rtc", "/dev/hpet", "/dev/vfio/vfio",
            "/dev/kvmfr0"
          ]
        '';
      };
    };
    virtualisation.spiceUSBRedirection.enable = true;
    programs.virt-manager.enable = true;

    environment.systemPackages = with pkgs; [
      vfioPkgs.looking-glass-client
      vfioPkgs.scream
      virt-viewer
    ];

    # 4. Declare the Windows domain (idempotent define on boot).
    environment.etc."libvirt/qemu/gamepass-win11.xml" = {
      text = winXml;
      mode = "0644";
    };
    systemd.services.gamepass-vm-define = {
      description = "Define the Game Pass Windows VM domain in libvirt";
      wantedBy = [ "multi-user.target" ];
      after = [ "libvirtd.service" ];
      script = ''
        set -euo pipefail
        xml=/etc/libvirt/qemu/gamepass-win11.xml
        if ${pkgs.libvirt}/bin/virsh dominfo gamepass-win11 >/dev/null 2>&1; then
          # The declared XML intentionally omits libvirt's generated UUID.
          # Reuse the existing UUID so `define` updates the domain instead of
          # attempting to create a second domain with the same name.
          uuid=$(${pkgs.libvirt}/bin/virsh domuuid gamepass-win11)
          tmp=$(mktemp)
          trap 'rm -f "$tmp"' EXIT
          ${pkgs.gnused}/bin/sed "/<name>gamepass-win11<\\/name>/a\\    <uuid>$uuid</uuid>" "$xml" > "$tmp"
          ${pkgs.libvirt}/bin/virsh define "$tmp"
        else
          ${pkgs.libvirt}/bin/virsh define "$xml"
        fi
      '';
      path = [pkgs.coreutils pkgs.gnused pkgs.libvirt];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # 5. User access to libvirt + kvm.
    users.users.j_kro.extraGroups = [ "libvirtd" "kvm" ];
  };
}

/*
 * INSTALL STEPS (run once, after `just deploy zephyr`):
 *  1. Create the disk:
 *       sudo mkdir -p /var/lib/libvirt/images
 *       sudo qemu-img create -f qcow2 /var/lib/libvirt/images/gamepass-win11.qcow2 200G
 *  2. Attach your Windows 11 ISO (edit the XML cdrom sdb, or use virt-manager).
 *  3. Start + open Looking Glass:
 *       sudo virsh start gamepass-win11
 *       looking-glass-client
 *  4. In Windows: install VirtIO drivers (E:\ from the virtio-win cdrom),
 *     install the Looking Glass host (B7), install Scream sender.
 *  5. Sign into the Xbox app with Game Pass Ultimate; install Forza Horizon 6.
 */
