{ lib, config, ... }:

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
            ${lib.optionalString (disk.bootOrder != null) "<boot order='${toString disk.bootOrder}'/>"}
          </disk>
        '' else if disk.type == "iscsi" then ''
          <disk type='network' device='disk'>
            <driver name='qemu' type='raw' cache='${disk.cache}'/>
            <source protocol='iscsi' name='${disk.targetIqn}/${disk.lun}'>
              <host name='${disk.portal.host}' port='${toString disk.portal.port}'/>
            </source>
            <target dev='${disk.target}' bus='virtio'/>
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
        ''
          <hostdev mode='subsystem' type='pci' managed='yes'>
            <driver name='vfio'/>
            <source>
              <address domain='${gpu.domain}' bus='${gpu.bus}' slot='${gpu.slot}' function='${gpu.function}'/>
            </source>
            <rom bar='${gpu.romBar}'/>
            <address type='pci' domain='0x0000' bus='0x06' slot='0x00' function='0x0'/>
          </hostdev>
        ''
      ) gpus;

      usbsXml = lib.concatMapStrings (usb: ''
        <hostdev mode='subsystem' type='usb' managed='yes'>
          <source startupPolicy='${usb.startupPolicy}'>
            <vendor id='${usb.vendor}'/>
            <product id='${usb.product}'/>
          </source>
          <address type='usb' bus='${usb.bus}' port='${usb.port}'/>
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
          <nvram template='/run/libvirt/nix-ovmf/edk2-i386-vars.fd' templateFormat='raw' format='raw'>${nvram}</nvram>
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
in
{
  # Write the generated XML to /etc/libvirt/qemu (libvirtd auto-loads)
  environment.etc."libvirt/qemu/${params.vm.name}.xml".text = generateDomainXml {
    inherit (params.vm) name uuid memory vcpu nvram;
    disks = params.vm.disks;
    networks = params.vm.networks;
    gpus = params.vm.gpus;
    usbs = params.vm.usbs;
  };
  
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