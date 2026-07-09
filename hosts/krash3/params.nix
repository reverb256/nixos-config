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
      # Whole-controller PCI passthrough for BOTH XHCI controllers so USB works
      # on ANY port, hotplug included:
      #   - 0a:00.3 (1022:149c, IOMMU group 20 — alone) → onboard ports
      #   - 02:00.0 (1022:43ee, group 15 — NIC-entangled) → chipset ports
      # Both are in vfio-pci.ids (hardware.nix). The per-device `usbs` entries
      # remain as a belt-and-suspenders fallback but are no longer required for
      # port-agnostic passthrough.
      controllers = [
        { vendor = "1022"; device = "149c"; bus = "0x0a"; slot = "0x00"; function = "0x3"; }
        { vendor = "1022"; device = "43ee"; bus = "0x02"; slot = "0x00"; function = "0x0"; }
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
    offset = 1069056;       # partition offset in sectors
    devices = [ "/dev/sdb" "/dev/sda" ];
    chunk = 64;             # raid0 chunk size in KB
  };

  vm = {
    name = "krash3-vm";
    uuid = "52b825d0-6b0a-4e19-b251-7ae312ccd5d0";
    memory = 20472;  # MiB (20 GiB)
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
        # E: drive — direct virtio-blk on the RAID partition. NO iSCSI target
        # in the path, so it survives NixOS rebuilds and reboots by construction.
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
        # Intel Bluetooth (8087:0029) — on chipset XHCI controller (02:00.0,
        # IOMMU group 15, NIC-entangled). NOT on the VFIO-passthrough Matisse
        # controller, so it MUST use per-device passthrough. Host can see it
        # (it appears in `lsusb` / info usbhost) so bus/device addressing works.
        vendor = "0x8087";
        product = "0x0029";
        bus = "1";
        device = "2";
        startupPolicy = "optional";
      }
      {
        # Zikway HID keyboard (3537:2106) — input device. Passed per-device so
        # it works REGARDLESS of which physical port it is plugged into. If the
        # device is on a chipset-port (group 15) the host sees it and binds it;
        # if it is on a Matisse-port (group 20, VFIO-passed whole-controller)
        # the host cannot see it and libvirt marks it missing=yes (non-fatal) —
        # it still arrives via the VFIO controller. Either way the keyboard works.
        vendor = "0x3537";
        product = "0x2106";
        bus = "0";
        port = "1";
        startupPolicy = "optional";
      }
      {
        # Sony DualShock 4 gamepad (054c:09cc)
        vendor = "0x054c";
        product = "0x09cc";
        bus = "0";
        port = "2";
        startupPolicy = "optional";
      }
      {
        # Logitech Unifying Receiver (046d:c52b) — multi-interface HID
        # (mouse + keyboard + consumer). Per-device passthrough so it works on
        # any port. NOTE: the `qemu:del capability='usb-host.hostdevice'` line
        # that previously stripped the keyboard HID interface has been REMOVED
        # from this file — without it libvirt uses the `hostdevice=/dev/bus/usb`
        # path which preserves all interfaces.
        vendor = "0x046d";
        product = "0xc52b";
        bus = "0";
        port = "4";
        startupPolicy = "optional";
      }
      {
        # PixArt USB Optical Mouse (04f2:0939)
        vendor = "0x04f2";
        product = "0x0939";
        bus = "0";
        port = "5";
        startupPolicy = "optional";
      }
    ];
  };
}