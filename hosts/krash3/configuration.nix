{ config, pkgs, lib, ... }:
let
  # Windows VM XML embedded INLINE — NEVER a separate file
  windowsDomainXml = ''
    <domain type='kvm'>
      <name>windows</name>
      <uuid>52b825d0-6b0a-4e19-b251-7ae312ccd5d0</uuid>
      <memory unit='KiB'>25165824</memory>
      <currentMemory unit='KiB'>25165824</currentMemory>
      <vcpu placement='static'>16</vcpu>
      <os>
        <type arch='x86_64' machine='pc-q35-10.2'>hvm</type>
        <loader readonly='yes' type='pflash' format='raw'>/run/libvirt/nix-ovmf/edk2-x86_64-code.fd</loader>
        <nvram template='/run/libvirt/nix-ovmf/edk2-i386-vars.fd' templateFormat='raw' format='raw'>/var/lib/libvirt/qemu/nvram/windows_VARS.fd</nvram>
      </os>
      <features>
        <acpi/><apic/>
        <hyperv mode='custom'>
          <relaxed state='on'/><vapic state='on'/><spinlocks state='on' retries='8191'/>
          <vpindex state='on'/><synic state='on'/><stimer state='on'/><reset state='on'/>
          <vendor_id state='on' value='KVM Hv'/><frequencies state='on'/>
          <reenlightenment state='on'/><tlbflush state='on'/><ipi state='on'/>
        </hyperv>
        <kvm><hidden state='on'/></kvm>
      </features>
      <cpu mode='host-model' check='none'>
        <topology sockets='1' dies='1' clusters='1' cores='8' threads='2'/>
      </cpu>
      <clock offset='localtime'><timer name='hypervclock' present='yes'/></clock>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>destroy</on_crash>
      <devices>
        <emulator>/run/libvirt/nix-emulators/qemu-system-x86_64</emulator>
        <disk type='file' device='disk'>
          <driver name='qemu' type='raw' cache='none'/>
          <source file='/var/lib/libvirt/images/c.raw'/>
          <target dev='vda' bus='virtio'/><boot order='1'/>
        </disk>
        <disk type='file' device='cdrom'>
          <driver name='qemu' type='raw'/>
          <source file='/var/lib/libvirt/images/virtio-win.iso'/>
          <target dev='sdd' bus='sata'/><readonly/>
        </disk>
        <controller type='sata' index='0'/><controller type='usb' index='0' model='qemu-xhci'/>
        <controller type='pci' index='0' model='pcie-root'/>
        <controller type='pci' index='1' model='pcie-root-port'/>
        <controller type='pci' index='2' model='pcie-root-port'/>
        <controller type='pci' index='3' model='pcie-root-port'/>
        <controller type='pci' index='4' model='pcie-root-port'/>
        <controller type='pci' index='5' model='pcie-root-port'/>
        <controller type='pci' index='6' model='pcie-root-port'/>
        <controller type='pci' index='7' model='pcie-root-port'/>
        <controller type='pci' index='8' model='pcie-root-port'/>
        <controller type='virtio-serial' index='0'/>
        <interface type='network'>
          <mac address='52:54:00:a5:e0:e0'/>
          <source network='default'/><model type='virtio'/>
        </interface>
        <interface type='direct'>
          <source dev='enp7s0' mode='bridge'/><model type='virtio'/>
        </interface>
        <input type='keyboard' bus='ps2'/><input type='mouse' bus='ps2'/>
        <graphics type='spice' port='5900' autoport='yes' listen='127.0.0.1'>
          <listen type='address' address='127.0.0.1'/>
        </graphics>
        <audio id='1' type='spice'/>
        <video><model type='qxl' ram='131072' vram='131072' vgamem='65536' heads='1'/></video>
        <hostdev mode='subsystem' type='pci' managed='yes'>
          <driver name='vfio'/>
          <source><address domain='0x0000' bus='0x08' slot='0x00' function='0x0'/></source>
          <rom bar='on' file='/var/lib/libvirt/images/gpu-rom.bin'/>
        </hostdev>
        <hostdev mode='subsystem' type='pci' managed='yes'>
          <driver name='vfio'/>
          <source><address domain='0x0000' bus='0x08' slot='0x00' function='0x1'/></source>
        </hostdev>
        <hostdev mode='subsystem' type='pci' managed='yes'>
          <driver name='vfio'/>
          <source><address domain='0x0000' bus='0x0a' slot='0x00' function='0x3'/></source>
        </hostdev>
        <watchdog model='itco' action='reset'/>
        <memballoon model='virtio'/>
        <channel type='unix'>
          <target type='virtio' name='org.qemu.guest_agent.0'/>
          <address type='virtio-serial' controller='0' bus='0' port='1'/>
        </channel>
      </devices>
      <seclabel type='none' model='none'/>
    </domain>
  '';
in {
  # Headless server guard
  services.xserver.enable = lib.mkForce false;
  services.displayManager.enable = lib.mkForce false;
  services.displayManager.sddm.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  imports = [
    ./hardware.nix
    ./services.nix
    ./hardware-configuration.nix
  ];

  # ── Network ─────────────────────────────────────────────
  networking.hostName = "krash3";
  networking.hostId = "deadbeef";
  networking.useDHCP = true;
  networking.interfaces.enp7s0.useDHCP = true;
  networking.nameservers = [ "127.0.0.1" ];
  networking.search = [ "lan" ];
  networking.networkmanager.enable = false;
  networking.dhcpcd.extraConfig = "nooption domain_name_servers";

  # ── Firewall ────────────────────────────────────────────
  networking.firewall.allowedTCPPorts = [ 22 445 2222 3260 ];

  # ── SSH ─────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # ── Users ──────────────────────────────────────────────
  users.mutableUsers = false;
  users.users = {
    root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ1lF6vw/QnBQAGW49nJQAlOssUYp0d1TmViLazBTFO9 krasheed@DESKTOP-OGFJPG1"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMKB2nv6oKIj5SWMrYzIE3K7tML0XQlKK+8bFEE/fHKM krasheed@DESKTOP-OGFJPG1"
    ];
    krash = {
      isNormalUser = true;
      extraGroups = [ "wheel" "libvirtd" ];
      hashedPassword = "$6$XM4f/B8LAg/hKjIT$OZ4gQj9Ol.A2dZH83BXMDqWJdU7aG1S5adoQ0ImNfjEQVX1sV7XAVvj/s72JfvnHxV3QGaW/rwNp.bQefrRy00";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM8tvIahh2d+ayiq1XFkeUDvlvJrGRCp2bkorRld96Du krash@Krash3"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK+vUa20eCtROzM8WaQ2FrGDLPPMGno+pAlhDVUF3C43 krash@DESKTOP-ONB6NLM"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFtIVTCtftMqJ1rcAlfccwKWwraQOSJtp0mSQxDhaAT2 j_kro@krash3"
      ];
    };
    j_kro = {
      isNormalUser = true;
      extraGroups = [ "wheel" "libvirtd" ];
      hashedPassword = "$6$wF9DUdOr20D1Jk6W$I.UA6S52wn3EoDL1UEsDlY/urMPqvGMJg1keHi/L/R/SwSYQeWgmuG/nF5ns57egnltuDdKVrOFjLysLpCrvA0";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvekxGk1YR/eF8llVmNk3C59BtgB+9DNvxLy2WjPEyb j_kro@zephyr"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIU9isFAwjVECiYVB0BoiAc1r5EXG5WbqgYErIrlj0VB j_kro@nexus"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFtIVTCtftMqJ1rcAlfccwKWwraQOSJtp0mSQxDhaAT2 j_kro@krash3"
        "***@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIM8thErkGjAacCICZxGcBd4oYP+GIoHDPHJ3kXGIc9IyAAAAEXNzaDpqX2tyby1jbHVzdGVy ssh:j_kro-cluster"
      ];
    };
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  # ── X11 / Display ───────────────────────────────────────

  # ── Write inline VM XML & define on every rebuild ───────
  system.activationScripts.windows-vm = lib.mkAfter ''
    cat > /var/lib/libvirt/images/windows-domain.xml << 'XMLEOF'
${windowsDomainXml}
XMLEOF
    chown root:libvirtd /var/lib/libvirt/images/windows-domain.xml
    chmod 640 /var/lib/libvirt/images/windows-domain.xml
  '';

  # ── SSH key dirs ────────────────────────────────────────
  system.activationScripts.ssh-keys = ''
    mkdir -p /home/krash/.ssh /home/j_kro/.ssh
    chmod 700 /home/krash/.ssh /home/j_kro/.ssh
  '';
}
