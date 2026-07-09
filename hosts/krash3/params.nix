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
      # Whole-controller PCI passthrough for the isolated onboard USB controller
      # (0000:0a:00.3, 1022:149c, group 20, alone in IOMMU group) — any device
      # on those ports passes through automatically.  The chipset controller
      # (02:00.0, group 15, NIC-entangled) cannot be passed; devices on those
      # ports use per-device USB passthrough via `usbs`.
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
        source = "/dev/md0";
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
        # IOMMU group 15). NOT on the VFIO-passthrough controller, so it MUST
        # use per-device passthrough. The other peripheral devices (Logitech
        # receiver, Zikway keyboard, PixArt mouse, Sony gamepad) are on the
        # VFIO-passthrough Matisse controller (0a:00.3) and reach the VM
        # automatically via the whole-controller PCI passthrough — they do NOT
        # need per-device entries here.
        vendor = "0x8087";
        product = "0x0029";
        bus = "1";
        device = "2";
        startupPolicy = "optional";
      }
    ];
  };
}