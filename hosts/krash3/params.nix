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
      vendor = "1022";
      device = "149c";
      bus = "0x0a";
      slot = "0x00";
      function = "0x3";
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
    name = "windows";
    uuid = "52b825d0-6b0a-4e19-b251-7ae312ccd5d0";
    memoryKiB = 20971520;   # 20 GiB
    vcpu = 16;
    cores = 8;
    threads = 2;
    cdisk = "c.raw";
    virtioIso = "/var/lib/libvirt/images/virtio-win.iso";
    gpuRom = "/var/lib/libvirt/images/gpu-rom.bin";
    macNAT = "52:54:00:a5:e0:e0";
    macMacvtap = "52:54:00:21:03:ae";
    nvram = "/var/lib/libvirt/qemu/nvram/windows_VARS.fd";
    iqn = "iqn.2025-06.lan.krash3:games";
  };
}
