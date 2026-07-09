# krash3 host parameters — single source of truth for hardware-specific values
{
  pci = {
    gpu = {
      vendor = "10de";
      device = "2882";
      bus = "0x08";
      slot = "0x00";
      function = "0x0";
    };
    gpuAudio = {
      vendor = "10de";
      device = "22be";
      bus = "0x08";
      slot = "0x00";
      function = "0x1";
    };
    usb = {
      # Whole-controller PCI passthrough of the ONBOARD Matisse XHCI only
      # (0000:0a:00.3, 1022:149c, IOMMU group 20 — alone, no NIC). Group 20 is
      # viable, so passing the whole controller makes EVERY device on the
      # onboard ports appear in the VM automatically — keyboard, mouse,
      # gamepad dongle, USB hubs, anything, including hotplug.
      #
      # The CHIPSET XHCI (0000:02:00.0, 1022:43ee) is NEVER passed: it shares
      # IOMMU group 15 with the host's Intel NIC/SATA/WiFi, so that group can
      # never be made viable ("group 15 is not viable" aborts QEMU). Devices on
      # chipset ports are still covered by the per-device `usbs` list + the
      # udev hotplug hook in declarative-vm.nix (vendor:product match).
      controllers = [
        { vendor = "1022"; device = "149c"; bus = "0x0a"; slot = "0x00"; function = "0x3"; }
      ];
    };
  };

  network = {
    hostName = "krash3";
    hostId = "deadbeef";
    interface = "enp7s0";
    ip = "10.1.1.150";
    gateway = "10.1.1.1";
  };

  raid = {
    offset = 1069056;
    devices = [ "/dev/sdb" "/dev/sda" ];
    chunk = 64;
  };

  vm = {
    name = "krash3-vm";
    uuid = "52b825d0-6b0a-4e19-b251-7ae312ccd5d0";
    memory = 20472;
    vcpu = 16;
    nvram = "/var/lib/libvirt/qemu/nvram/krash3-vm_VARS.fd";
    iqn = "iqn.2025-06.lan.krash3:games";

    disks = [
      {
        type = "virtio-file";
        target = "vda";
        source = "/var/lib/libvirt/images/c.raw";
        bootOrder = 1;
        iothread = 1;
        cache = "writeback";
      }
      {
        type = "block";
        target = "vdb";
        source = "/dev/md0p1";
        cache = "none";
      }
    ];

    networks = [
      {
        type = "bridge";
        bridge = "virbr0";
        mac = "52:54:00:a5:e0:e0";
        model = "virtio";
        bus = "01";
        slot = "0x00";
      }
      {
        type = "macvtap";
        dev = "enp7s0";
        mac = "52:54:00:7e:42:55";
        model = "virtio";
        mode = "bridge";
        bus = "02";
        slot = "0x00";
      }
    ];

    gpus = [
      {
        domain = "0x0000";
        bus = "0x08";
        slot = "0x00";
        function = "0x0";
        romBar = "off";
      }
    ];

    usbs = [
      {
        vendor = "0x8087"; product = "0x0029"; bus = "1"; device = "2"; startupPolicy = "optional";
      }
      {
        vendor = "0x3537"; product = "0x2106"; bus = "0"; port = "1"; startupPolicy = "optional";
      }
      {
        vendor = "0x054c"; product = "0x09cc"; bus = "0"; port = "2"; startupPolicy = "optional";
      }
      {
        vendor = "0x046d"; product = "0xc52b"; bus = "0"; port = "4"; startupPolicy = "optional";
      }
      {
        vendor = "0x04f2"; product = "0x0939"; bus = "0"; port = "5"; startupPolicy = "optional";
      }
      {
        vendor = "0x05e3"; product = "0x0610"; startupPolicy = "optional";
      }
      {
        vendor = "0x05e3"; product = "0x0612"; startupPolicy = "optional";
      }
    ];
  };
}
