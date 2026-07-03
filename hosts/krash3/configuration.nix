{
  config, pkgs, lib, ...
}:
let
  # Windows VM XML embedded INLINE — matches live libvirt config exactly
  windowsDomainXml = ''<domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
  <name>windows</name>
  <uuid>52b825d0-6b0a-4e19-b251-7ae312ccd5d0</uuid>
  <memory unit='KiB'>20971520</memory>
  <currentMemory unit='KiB'>20971520</currentMemory>
  <vcpu placement='static'>16</vcpu>
  <iothreads>2</iothreads>
  <cputune>
    <vcpupin vcpu='0' cpuset='0'/>
    <vcpupin vcpu='1' cpuset='1'/>
    <vcpupin vcpu='2' cpuset='2'/>
    <vcpupin vcpu='3' cpuset='3'/>
    <vcpupin vcpu='4' cpuset='4'/>
    <vcpupin vcpu='5' cpuset='5'/>
    <vcpupin vcpu='6' cpuset='6'/>
    <vcpupin vcpu='7' cpuset='7'/>
    <vcpupin vcpu='8' cpuset='12'/>
    <vcpupin vcpu='9' cpuset='13'/>
    <vcpupin vcpu='10' cpuset='14'/>
    <vcpupin vcpu='11' cpuset='15'/>
    <vcpupin vcpu='12' cpuset='16'/>
    <vcpupin vcpu='13' cpuset='17'/>
    <vcpupin vcpu='14' cpuset='18'/>
    <vcpupin vcpu='15' cpuset='19'/>
    <emulatorpin cpuset='8,20'/>
    <iothreadpin iothread='1' cpuset='8,20'/>
    <iothreadpin iothread='2' cpuset='8,20'/>
  </cputune>
  <os firmware='efi'>
    <type arch='x86_64' machine='pc-q35-10.2'>hvm</type>
    <firmware>
      <feature enabled='no' name='enrolled-keys'/>
      <feature enabled='no' name='secure-boot'/>
    </firmware>
    <loader readonly='yes' type='pflash' format='raw'>/run/libvirt/nix-ovmf/edk2-x86_64-code.fd</loader>
    <nvram template='/run/libvirt/nix-ovmf/edk2-i386-vars.fd' templateFormat='raw' format='raw'>/var/lib/libvirt/qemu/nvram/windows_VARS.fd</nvram>
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
    <kvm>
      <hidden state='on'/>
    </kvm>
  </features>
  <cpu mode='host-model' check='none'>
    <topology sockets='1' dies='1' clusters='1' cores='8' threads='2'/>
  </cpu>
  <clock offset='utc'>
    <timer name='hypervclock' present='yes'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <emulator>/run/libvirt/nix-emulators/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw' cache='writeback' iothread='1'/>
      <source file='/var/lib/libvirt/images/c.raw'/>
      <target dev='vda' bus='virtio'/>
      <boot order='1'/>
      <address type='pci' domain='0x0000' bus='0x05' slot='0x00' function='0x0'/>
    </disk>
<controller type='sata' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x1f' function='0x2'/>
    </controller>
    <controller type='usb' index='0' model='qemu-xhci'>
      <address type='pci' domain='0x0000' bus='0x03' slot='0x00' function='0x0'/>
    </controller>
    <controller type='pci' index='0' model='pcie-root'/>
    <controller type='pci' index='1' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='1' port='0x10'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0' multifunction='on'/>
    </controller>
    <controller type='pci' index='2' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='2' port='0x11'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x1'/>
    </controller>
    <controller type='pci' index='3' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='3' port='0x12'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x2'/>
    </controller>
    <controller type='pci' index='4' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='4' port='0x13'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x3'/>
    </controller>
    <controller type='pci' index='5' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='5' port='0x14'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x4'/>
    </controller>
    <controller type='pci' index='6' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='6' port='0x15'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x5'/>
    </controller>
    <controller type='pci' index='7' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='7' port='0x16'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x6'/>
    </controller>
    <controller type='pci' index='8' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='8' port='0x17'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x7'/>
    </controller>
    <controller type='pci' index='9' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='9' port='0x18'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </controller>
    <controller type='virtio-serial' index='0'>
      <address type='pci' domain='0x0000' bus='0x04' slot='0x00' function='0x0'/>
    </controller>
    <interface type='bridge'>
      <mac address='52:54:00:a5:e0:e0'/>
      <source bridge='virbr0'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
    </interface>
    <interface type='direct'>
      <mac address='52:54:00:7e:42:55'/>
      <source dev='enp7s0' mode='bridge'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x02' slot='0x00' function='0x0'/>
    </interface>
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
      <address type='virtio-serial' controller='0' bus='0' port='1'/>
    </channel>
    <input type='keyboard' bus='ps2'/>
    <input type='mouse' bus='ps2'/>
<audio id='1' type='none'/>
<hostdev mode='subsystem' type='pci' managed='yes'>
      <driver name='vfio'/>
      <source>
        <address domain='0x0000' bus='0x08' slot='0x00' function='0x0'/>
      </source>
      <rom bar='off'/>
      <address type='pci' domain='0x0000' bus='0x06' slot='0x00' function='0x0'/>
    </hostdev>
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <driver name='vfio'/>
      <source>
        <address domain='0x0000' bus='0x08' slot='0x00' function='0x1'/>
      </source>
      <address type='pci' domain='0x0000' bus='0x07' slot='0x00' function='0x0'/>
    </hostdev>
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <driver name='vfio'/>
      <source>
        <address domain='0x0000' bus='0x0a' slot='0x00' function='0x3'/>
      </source>
      <address type='pci' domain='0x0000' bus='0x08' slot='0x00' function='0x0'/>
    </hostdev>
    <hostdev mode='subsystem' type='usb' managed='yes'>
      <source startupPolicy='optional'>
        <vendor id='0x3537'/>
        <product id='0x2106'/>
      </source>
      <address type='usb' bus='0' port='1'/>
    </hostdev>
    <hostdev mode='subsystem' type='usb' managed='yes'>
      <source startupPolicy='optional'>
        <vendor id='0x054c'/>
        <product id='0x09cc'/>
      </source>
      <address type='usb' bus='0' port='2'/>
    </hostdev>
    <hostdev mode='subsystem' type='usb' managed='yes'>
      <source>
        <vendor id='0x8087'/>
        <product id='0x0029'/>
      </source>
      <address type='usb' bus='0' port='3'/>
    </hostdev>
    <watchdog model='itco' action='reset'/>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x09' slot='0x00' function='0x0'/>
    </memballoon>
  </devices>
  <seclabel type='none' model='none'/>
  <qemu:capabilities>
    <qemu:del capability='usb-host.hostdevice'/>
  </qemu:capabilities>
</domain>'';
in {
  # ── Libvirt ──────────────────────────────────────────────
  virtualisation.libvirtd = {
  # ── Performance tuning ──
    enable = true;
    qemuVerbatimConfig = ''
      max_memlock = 26843545600
    '';
  };

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
  time.timeZone = lib.mkForce "America/Winnipeg";
  networking.hostName = "krash3";
  networking.hostId = "deadbeef";
  networking.useDHCP = true;
  networking.interfaces.enp7s0.useDHCP = true;
  networking.nameservers = [ "127.0.0.1" ];
  networking.search = [ "lan" ];
  networking.networkmanager.enable = false;
  networking.dhcpcd.extraConfig = "nooption domain_name_servers";

  # ── Firewall ────────────────────────────────────────────
  networking.firewall.allowedTCPPorts = [ 53 ];   # DNS is global (needed by unbound for 10.1.1.0/24 clients)
  networking.firewall.extraInputRules = ''
    # SSH — restrict to LAN
    ip saddr { 10.1.1.0/24 } tcp dport 22 accept

    # Samba/SMB — restrict to libvirt VM network only (Windows VM via virbr0)
    iifname "virbr0" tcp dport { 139, 445 } accept
    iifname "virbr0" udp dport { 137, 138 } accept

    # iSCSI — restrict to LAN + libvirt VM network
    ip saddr { 10.1.1.0/24, 192.168.122.0/24 } tcp dport 3260 accept

    # Unbound DNS — restrict to LAN (access-control already set in unbound config)
    ip saddr { 10.1.1.0/24, 127.0.0.0/8, 192.168.122.0/24 } udp dport 53 accept
    ip saddr { 10.1.1.0/24, 127.0.0.0/8, 192.168.122.0/24 } tcp dport 53 accept

    # alt SSH (2222) — restrict to LAN
    ip saddr 10.1.1.0/24 tcp dport 2222 accept

    # k3s agent API — loopback only (default)
  '';
  services.avahi.enable = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;
  networking.nftables.enable = lib.mkForce true;
  systemd.services.dhcpcd.restartIfChanged = false;

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
  programs.niri.enable = lib.mkForce false;
  services.flatpak.enable = lib.mkForce false;
  services.flatpak-kde.enable = lib.mkForce false;

  # ── Write inline VM XML & define on every rebuild ───────
  system.activationScripts.windows-vm = lib.mkAfter ''
    # Create libvirt default network WITHOUT dnsmasq (avoids port 53 conflict with unbound)
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

    cat > /var/lib/libvirt/images/windows-domain.xml << 'XMLEOF'
${windowsDomainXml}
XMLEOF
    chown root:libvirtd /var/lib/libvirt/images/windows-domain.xml
    chmod 640 /var/lib/libvirt/images/windows-domain.xml
    # Define domain from the generated XML so virsh knows it
    virsh define /var/lib/libvirt/images/windows-domain.xml 2>/dev/null || true
    virsh autostart windows 2>/dev/null || true

  '';

  # ── SSH key dirs ────────────────────────────────────────
  system.activationScripts.ssh-keys = ''
    mkdir -p /home/krash/.ssh /home/j_kro/.ssh
    chmod 700 /home/krash/.ssh /home/j_kro/.ssh
  '';

  # ── SOPS Secrets ────────────────────────────────────────
  # ── Distributed Builds — never build locally ──
  nix.distributedBuilds = true;
  nix.settings = {
    builders = lib.mkDefault "@/etc/nix/machines";
    builders-use-substitutes = true;
    max-jobs = 0;
  };

  sops = {
    age = {
      keyFile = "/etc/nixos/.age/key.txt";
      sshKeyPaths = [];
    };
    secrets = {
      "gemini-api-key" = {
        sopsFile = ../../secrets/ai/gemini-api-key.yaml;
        format = "binary";
        path = "/run/secrets/gemini-api-key";
        owner = "j_kro";
        group = "users";
        mode = "0444";
      };
      "k3s-cluster-token" = {
        sopsFile = ../../secrets/k8s/k3s-cluster-token.yaml;
        path = "/run/secrets/k3s-cluster-token";
        format = "binary";
        owner = "root";
        group = "root";
        mode = "0444";
      };
    };
  };
  # ── Performance tuning ──
  boot.kernel.sysctl."vm.nr_hugepages" = 24;

}