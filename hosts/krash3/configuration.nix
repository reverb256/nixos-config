{ config, pkgs, lib, inputs, ... }:
let
  inherit (import ../../mesh-keys.nix) meshKeys;
in {
  imports = [
    ./hardware-configuration.nix
  ];

  # ── Boot ────────────────────────────────────────────────
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
  boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.kernelParams = [
    "amd_iommu=on" "iommu=pt" "kvm.ignore_msrs=1"
    "video=efifb:off"
    "console=ttyS0,115200"
  ];
  boot.initrd.kernelModules = [ "vfio" "vfio_iommu_type1" "virtio_pci" "virtio_blk" ];
  boot.blacklistedKernelModules = [ "nvidia" "nvidia_drm" "nvidia_modeset" "nvidia_uvm" ];
  boot.initrd.systemd.enable = false;
  boot.initrd.postMountCommands = ''
    stage2InitRel=''${stage2Init#/}
    if [ ! -e "$targetRoot/$stage2InitRel" ]; then
      mkdir -m 0755 -p $targetRoot/proc $targetRoot/sys $targetRoot/dev $targetRoot/run 2>/dev/null
      mount --move /proc $targetRoot/proc 2>/dev/null
      mount --move /sys $targetRoot/sys 2>/dev/null
      mount --move /dev $targetRoot/dev 2>/dev/null
      mount --move /run $targetRoot/run 2>/dev/null
      exec env -i $(type -P switch_root) "$targetRoot" "/$stage2InitRel"
    fi
    stage2Init="/$stage2InitRel"
  '';

  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
  };

  zramSwap.enable = true;

  networking.hostName = "krash3";
  networking.hostId = "deadbeef";
  networking.useDHCP = true;
  networking.bridges.br0 = { interfaces = [ "enp6s0" ]; };
  networking.interfaces = {
    enp6s0.useDHCP = false;
    br0 = {
      ipv4.addresses = [{
        address = "10.1.1.150";
        prefixLength = 24;
      }];
    };
  };
  networking.defaultGateway = "10.1.1.1";
  networking.nameservers = [ "127.0.0.1" "::1" ];
  networking.search = [ "lan" ];
  networking.dhcpcd.extraConfig = "nooption domain_name_servers";

  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [ "127.0.0.1" "::1" "10.1.1.150" ];
        access-control = [ "127.0.0.0/8 allow" "10.1.1.0/24 allow" "::1 allow" ];
        private-domain = "lan";
        local-zone = "\"lan.\" static";
        local-data = [
          "\"maplespike.lan. A 10.1.1.150\""
          "\"searxng.lan. A 127.0.0.1\""
          "\"vane.lan. A 127.0.0.1\""
          "\"haven.lan. A 10.1.1.100\""
        ];
      };
      forward-zone = [{
        name = ".";
        forward-addr = [ "10.1.1.100" ];
      }];
    };
  };

  virtualisation.libvirtd = {
    enable = true;
    qemu.package = pkgs.qemu_kvm;
    onBoot = "start";
    onShutdown = "shutdown";
  };
  virtualisation.spiceUSBRedirection.enable = true;

  systemd.tmpfiles.rules = [
    "f /var/lib/libvirt/images/c.raw 0640 root libvirtd - -"
  ];

  systemd.services.assemble-games-raid = {
    wantedBy = [ "local-fs.target" ];
    before = [ "local-fs.target" ];
    path = [ pkgs.mdadm pkgs.util-linux ];
    script = ''
      offset=$((1069056 * 512))
      ${pkgs.util-linux}/bin/losetup -o $offset /dev/loop10 /dev/sdb
      ${pkgs.util-linux}/bin/losetup -o $offset /dev/loop11 /dev/sda
      ${pkgs.mdadm}/bin/mdadm --build /dev/md0 --level=raid0 --chunk=64 \
        --raid-devices=2 /dev/loop10 /dev/loop11
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  systemd.services.libvirt-autostart-windows = {
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" "assemble-games-raid.service" ];
    script = ''
      if [ -f /var/lib/libvirt/images/windows-domain.xml ]; then
        ${pkgs.libvirt}/bin/virsh define /var/lib/libvirt/images/windows-domain.xml
      elif [ -f /etc/nixos/windows-domain.xml ]; then
        ${pkgs.libvirt}/bin/virsh define /etc/nixos/windows-domain.xml
      fi
      ${pkgs.libvirt}/bin/virsh start windows 2>/dev/null || true
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  environment.systemPackages = with pkgs; [
    virt-manager libvirt virtio-win
  ];

  networking.firewall.allowedTCPPorts = [ 22 ];
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  services.xserver.enable = false;
  services.displayManager.enable = false;

  users.mutableUsers = false;
  users.users = {
    root.openssh.authorizedKeys.keys = meshKeys.root;
    krash = {
      isNormalUser = true;
      extraGroups = [ "wheel" "libvirtd" ];
      password = "0818";
      openssh.authorizedKeys.keys = meshKeys.krash or [];
    };
    j_kro = {
      isNormalUser = true;
      extraGroups = [ "wheel" "libvirtd" ];
      password = "50161";
      openssh.authorizedKeys.keys = meshKeys.j_kro;
    };
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  system.activationScripts.windows-vm = ''
    if [ -f /etc/nixos/windows-domain.xml ]; then
      cp /etc/nixos/windows-domain.xml /var/lib/libvirt/images/windows-domain.xml
      chown root:libvirtd /var/lib/libvirt/images/windows-domain.xml
      chmod 640 /var/lib/libvirt/images/windows-domain.xml
    fi
  '';

  # ── Lix (Nix implementation fork) ─────────────────────────
  services.lix.enable = true;

  system.stateVersion = "26.05";
}
