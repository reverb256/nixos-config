{ lib, config, pkgs, ... }:

let
  params = import ./params.nix;

  # Simple XML generator for krash3-vm
  generateDomainXml = { name, uuid, memory, vcpu, disks, networks, gpus, usbs, nvram }:
    let
      disksXml = lib.concatMapStrings (disk:
      if disk.type == "virtio-file" then ''
          <disk type='file' device='disk'>
            <driver name='qemu' type='raw' cache='${disk.cache}' ${lib.optionalString (disk.iothread != null) "iothread='${toString disk.iothread}'"}/>
            <source file='${disk.source}'/>
            <target dev='${disk.target}' bus='virtio'/>
            ${lib.optionalString (disk.bootOrder or null != null) "<boot order='${toString disk.bootOrder}'/>"}
          </disk>
        '' else if disk.type == "block" then ''
          <disk type='block' device='disk'>
            <driver name='qemu' type='raw' cache='${disk.cache}'/>
            <source dev='${disk.source}'/>
            <target dev='${disk.target}' bus='virtio'/>
            ${lib.optionalString (disk.bootOrder or null != null) "<boot order='${toString disk.bootOrder}'/>"}
          </disk>
        '' else ""
      ) disks;

      networksXml = lib.concatMapStrings (net:
        if net.type == "bridge" then ''
          <interface type='bridge'>
            <mac address='${net.mac}'/>
            <source bridge='${net.bridge}'/>
            <model type='${net.model}'/>
            <address type='pci' domain='0x0000' bus='0x${net.bus}' slot='${net.slot}' function='0x0'/>
          </interface>
        '' else if net.type == "macvtap" then ''
          <interface type='direct'>
            <mac address='${net.mac}'/>
            <source dev='${net.dev}' mode='${net.mode}'/>
            <model type='${net.model}'/>
            <address type='pci' domain='0x0000' bus='0x${net.bus}' slot='${net.slot}' function='0x0'/>
          </interface>
        '' else ""
      ) networks;

      gpusXml = lib.concatMapStrings (gpu:
        # Emit both GPU functions (0x0 = video, 0x1 = audio) so passthrough
        # matches the working windows domain exactly.
        let
          func0 = ''
            <hostdev mode='subsystem' type='pci' managed='yes'>
              <driver name='vfio'/>
              <source>
                <address domain='${gpu.domain}' bus='${gpu.bus}' slot='${gpu.slot}' function='0x0'/>
              </source>
              <rom bar='on' file='/var/lib/libvirt/images/gpu-rom.bin'/>
              <address type='pci' domain='0x0000' bus='0x06' slot='0x00' function='0x0'/>
            </hostdev>
          '';
          func1 = ''
            <hostdev mode='subsystem' type='pci' managed='yes'>
              <driver name='vfio'/>
              <source>
                <address domain='${gpu.domain}' bus='${gpu.bus}' slot='${gpu.slot}' function='0x1'/>
              </source>
              <address type='pci' domain='0x0000' bus='0x07' slot='0x00' function='0x0'/>
            </hostdev>
          '';
        in func0 + func1
      ) gpus;

      usbsXml = lib.concatMapStrings (usb: ''
        <hostdev mode='subsystem' type='usb' managed='yes'>
          <source startupPolicy='${usb.startupPolicy}'>
            <vendor id='${usb.vendor}'/>
            <product id='${usb.product}'/>
          </source>
        </hostdev>
      '') usbs;
    in ''
      <domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
        <name>${name}</name>
        <uuid>${uuid}</uuid>
        <memory unit='KiB'>${toString (memory * 1024)}</memory>
        <currentMemory unit='KiB'>${toString (memory * 1024)}</currentMemory>
        <vcpu placement='static'>${toString vcpu}</vcpu>
        <iothreads>2</iothreads>
        <cpu mode='host-model' check='none'/>
        <os firmware='efi'>
          <type arch='x86_64' machine='pc-q35-10.2'>hvm</type>
          <firmware>
            <feature enabled='no' name='enrolled-keys'/>
            <feature enabled='no' name='secure-boot'/>
          </firmware>
          <loader readonly='yes' type='pflash' format='raw'>/run/libvirt/nix-ovmf/edk2-x86_64-code.fd</loader>
          <nvram template='/run/libvirt/nix-ovmf/edk2-i386-vars.fd' templateFormat='raw'>${nvram}</nvram>
        </os>
        <features>
          <acpi/>
          <apic/>
          <hyperv mode='custom'>
            <relaxed state='on'/>
            <vapic state='on'/>
            <spinlocks state='on' retries='8191'/>
            <vpindex state='on'/>
            <synic state='on'/>
            <stimer state='on'/>
            <reset state='on'/>
            <vendor_id state='on' value='KVM Hv'/>
            <frequencies state='on'/>
            <reenlightenment state='on'/>
            <tlbflush state='on'/>
            <ipi state='on'/>
          </hyperv>
          <kvm><hidden state='on'/></kvm>
        </features>
        <clock offset='utc'>
          <timer name='hypervclock' present='yes'/>
        </clock>
        <on_poweroff>destroy</on_poweroff>
        <on_reboot>restart</on_reboot>
        <on_crash>destroy</on_crash>
        <devices>
          <emulator>/run/current-system/sw/bin/qemu-system-x86_64</emulator>
          <controller type='sata' index='0'>
            <address type='pci' domain='0x0000' bus='0x00' slot='0x1f' function='0x2'/>
          </controller>
          <controller type='usb' index='0' model='qemu-xhci'>
            <address type='pci' domain='0x0000' bus='0x03' slot='0x00' function='0x0'/>
          </controller>
          ${disksXml}
          <channel type='unix'>
            <target type='virtio' name='org.qemu.guest_agent.0'/>
            <address type='virtio-serial' controller='0' bus='0' port='1'/>
          </channel>
          <input type='keyboard' bus='ps2'/>
          <input type='mouse' bus='ps2'/>
          <audio id='1' type='none'/>
          ${networksXml}
          ${gpusXml}
          ${usbsXml}
          <watchdog model='itco' action='reset'/>
          <memballoon model='virtio'>
            <address type='pci' domain='0x0000' bus='0x09' slot='0x00' function='0x0'/>
          </memballoon>
        </devices>
        <seclabel type='none' model='none'/>
        <qemu:capabilities>
          <qemu:del capability='usb-host.hostdevice'/>
        </qemu:capabilities>
      </domain>
    '';

  # ── USB hotplug: auto-attach/detach devices to the running VM ──
  # libvirt does NOT hotplug host USB devices by default. This wires:
  #   1. A libvirt qemu hook that attaches already-present USB devices
  #      when the VM starts (and detaches on stop), matched by vendor:product.
  #   2. A udev rule that fires on USB plug/unplug and calls the hotplug
  #      script, so devices work whether plugged before OR after boot.
  # All 3 known devices pass through; krash3 has no USB peripherals that
  # must stay on the host, so the hook is safe to run unconditionally.
  vmName = params.vm.name;

  # USB device match-list for the hotplug script's case filter.
  usbMatchList = lib.concatMapStrings (usb: "${usb.vendor}:${usb.product}|") params.vm.usbs;

  # Script invoked by udev on USB add/remove. Attaches/detaches the matching
  # device (by vendor:product) to the running VM.
  hotplugScript = pkgs.writeScriptBin "krash3-usb-hotplug" ''
    #!/usr/bin/env bash
    set -euo pipefail
    ACTION="$1"      # add | remove
    BUS="$2"         # usb bus from udev (e.g. 1-2)
    VENDOR="$3"      # 0x3537
    PRODUCT="$4"     # 0x2106
    VM="${vmName}"
    VIRSH="${pkgs.libvirt}/bin/virsh"
    # Only act on the USB devices we intend to pass through.
    case "$VENDOR:$PRODUCT" in
      ${usbMatchList}
        ;;
      *) exit 0 ;;
    esac
    DEVXML=$(mktemp)
    cat > "$DEVXML" <<XML
      <hostdev mode='subsystem' type='usb' managed='yes'>
        <source startupPolicy='optional'>
          <vendor id='$VENDOR'/>
          <product id='$PRODUCT'/>
        </source>
      </hostdev>
    XML
    if [ "$ACTION" = "add" ]; then
      $VIRSH attach-device "$VM" "$DEVXML" --live --persistent 2>&1 || true
    elif [ "$ACTION" = "remove" ]; then
      $VIRSH detach-device "$VM" "$DEVXML" --live --persistent 2>&1 || true
    fi
    rm -f "$DEVXML"
  '';

  # libvirt qemu hook: attach present USB devices when the VM starts.
  qemuHook = pkgs.writeScriptBin "qemu-hook" ''
    #!/usr/bin/env bash
    set -euo pipefail
    VM="$1"; ACTION="$2"
    VIRSH="${pkgs.libvirt}/bin/virsh"
    [ "$VM" = "${vmName}" ] || exit 0
    [ "$ACTION" = "started" ] || exit 0
    ${lib.concatMapStrings (usb: ''
      DEVXML=$(mktemp); cat > "$DEVXML" <<XML
      <hostdev mode='subsystem' type='usb' managed='yes'>
        <source startupPolicy='optional'>
          <vendor id='${usb.vendor}'/>
          <product id='${usb.product}'/>
        </source>
      </hostdev>
      XML
      ${pkgs.libvirt}/bin/virsh attach-device "${vmName}" "$DEVXML" --live --persistent 2>&1 || true
      rm -f "$DEVXML"
    '') params.vm.usbs}
  '';

  # udev rule body (vendor list from params).
  usbVendorList = lib.concatMapStringsSep "|" (usb: usb.vendor) params.vm.usbs;
in
{
  # Write the generated XML to the path libvirtd actually loads on NixOS
  # (/var/lib/libvirt/qemu/), then define + autostart the domain from it so
  # the RUNNING domain matches the DECLARATIVE config (named krash3-vm, not
  # the legacy imperative "windows" domain). This closes the gap where every
  # declarative change was a no-op because libvirtd never loaded the XML.
  environment.etc."libvirt/qemu/${params.vm.name}.xml".text = generateDomainXml {
    inherit (params.vm) name uuid memory vcpu nvram;
    disks = params.vm.disks;
    networks = params.vm.networks;
    gpus = params.vm.gpus;
    usbs = params.vm.usbs;
  };

  # Hotplug script + libvirt qemu hook (made executable on the PATH).
  environment.systemPackages = [ hotplugScript qemuHook ];

  # libvirt qemu hook: symlink into the hooks dir libvirtd watches.
  environment.etc."libvirt/hooks/qemu".source = "${qemuHook}/bin/qemu-hook";
  environment.etc."libvirt/hooks/qemu".mode = "0755";

  # udev rule: fire hotplug script on USB add/remove for our devices.
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ACTION=="add", ATTR{idVendor}=="${usbVendorList}", RUN+="${hotplugScript}/bin/krash3-usb-hotplug add %k $attr{idVendor} $attr{idProduct}"
    SUBSYSTEM=="usb", ACTION=="remove", ATTR{idVendor}=="${usbVendorList}", RUN+="${hotplugScript}/bin/krash3-usb-hotplug remove %k $attr{idVendor} $attr{idProduct}"
  '';

  system.activationScripts.krash3-vm-define = lib.mkAfter ''
    # Ensure libvirtd is up before we define
    mkdir -p /var/lib/libvirt/qemu
    # Define (or redefine) the domain from the declarative XML.
    # virsh define is idempotent: re-running updates the existing domain.
    ${pkgs.libvirt}/bin/virsh define /etc/libvirt/qemu/krash3-vm.xml 2>&1 || true
    ${pkgs.libvirt}/bin/virsh autostart krash3-vm 2>&1 || true
  '';

  # Keep the old network activation (needed for virbr0)
  system.activationScripts.libvirt-network = lib.mkAfter ''
    # Create libvirt default network WITHOUT dnsmasq (avoids port 53 conflict with unbound)
    mkdir -p /var/lib/libvirt/images
    cat > /var/lib/libvirt/images/virbr0-net.xml << 'NETEOF'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <dns enable='no'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.10' end='192.168.122.100'/>
    </dhcp>
  </ip>
</network>
NETEOF
    virsh net-define /var/lib/libvirt/images/virbr0-net.xml 2>/dev/null || true
    virsh net-autostart default 2>/dev/null || true
    virsh net-start default 2>/dev/null || true
  '';
}
