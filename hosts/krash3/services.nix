{ config, pkgs, lib, ... }:
let
  params = import ./params.nix;
  inherit (params) vm;
in {
  # ── k3s cluster agent ── joins cluster as agent node
  services.k3s-cluster = {
    enable = true;
    role = "agent";
    nodeName = "krash3";
    nodeIP = "10.1.1.150";
    tokenFile = "/run/secrets/k3s-cluster-token";
    flannelIface = "enp7s0";
  };

  # ── Unbound DNS ──
  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [ "127.0.0.1" "::1" "10.1.1.150" ];
        access-control = [ "127.0.0.0/8 allow" "10.1.1.0/24 allow" "::1 allow" ];
        private-domain = "lan";
        local-data = [
          # Services (Caddy-proxied via VIP 10.1.1.100 for HA)
          "\"maplespike.lan. A 10.1.1.100\""
          "\"api.maplespike.lan. A 10.1.1.100\""
          "\"searxng.lan. A 10.1.1.100\""
          "\"search.lan. A 10.1.1.100\""
          "\"vane.lan. A 10.1.1.100\""
          "\"haven.lan. A 10.1.1.100\""
          "\"ai-inference.lan. A 10.1.1.100\""
          "\"auth.lan. A 10.1.1.100\""
          "\"grafana.lan. A 10.1.1.100\""
          "\"n8n.lan. A 10.1.1.100\""
          "\"gitea.lan. A 10.1.1.100\""
          # Host records (direct IPs)
          "\"nexus.lan. A 10.1.1.120\""
          "\"zephyr.lan. A 10.1.1.110\""
          "\"forge.lan. A 10.1.1.130\""
          "\"sentry.lan. A 10.1.1.140\""
          "\"krash3.lan. A 10.1.1.150\""
          # k3s cluster VIP (keepalived)
          "\"k3s-api.lan. A 10.1.1.100\""
          "\"cluster.lan. A 10.1.1.100\""
        ];
      };
      forward-zone = [{
        name = ".";
        forward-addr = [ "10.1.1.100" ];
      }];
    };
  };

  # ── Libvirtd ──
  virtualisation.libvirtd = {
    enable = true;
    qemu.package = pkgs.qemu_kvm;
    qemu.swtpm.enable = true;
    onBoot = "start";
    onShutdown = "shutdown";
  };
  virtualisation.spiceUSBRedirection.enable = true;
  systemd.tmpfiles.rules = [ "f /var/lib/libvirt/images/${vm.cdisk} 0640 root kvm - -" ];

  # ── iSCSI target ──
  # iSCSI target depends on RAID being assembled first
  systemd.services.iscsi-target = {
    after = [ "assemble-games-raid.service" ];
    requires = [ "assemble-games-raid.service" ];
    serviceConfig.ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $$(seq 1 30); do if [ -b /dev/md0p1 ]; then exit 0; fi; sleep 2; done; exit 1'";
  };
  services.target = {
    enable = true;
    config = {
      storage_objects = [{
        plugin = "block"; name = "games-raid"; dev = "/dev/md0p1";
        attributes = { block_size = 512; emulate_write_cache = 0; unmap_granularity = 512; };
      }];
      targets = [{
        fabric = "iscsi"; wwn = "${vm.iqn}";
        tpgs = [{
          tag = 1; enable = true;
          portals = [
            { ip_address = "192.168.122.1"; port = 3260; }
            { ip_address = "10.1.1.150"; port = 3260; }
          ];
          luns = [{ index = 0; alias = "games-raid"; storage_object = "/backstores/block/games-raid"; }];
          attributes = { authentication = 0; generate_node_acls = 1; demo_mode_write_protect = 0; demo_mode_discovery = 1; };
        }];
      }];
    };
  };

  # ── Samba ──
  services.samba = {
    enable = true; openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP"; "server string" = "krash3"; "netbios name" = "krash3";
        security = "user"; "map to guest" = "Bad User"; "guest account" = "nobody";
      };
    };
  };

  # ── k3s token fetch ── fetches token from control plane
  systemd.services.k3s-token-fetch = {
    wantedBy = [ "multi-user.target" ];
    before = [ "k3s.service" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    path = [ pkgs.openssh pkgs.coreutils ];
    script = ''
      ssh -o StrictHostKeyChecking=accept-new j_kro@nexus cat /persistent/etc/k3s-cluster-token > /run/secrets/k3s-cluster-token
      chmod 600 /run/secrets/k3s-cluster-token
    '';
  };

  # ── VM autostart ──
  systemd.services.libvirt-autostart-windows = {
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" "assemble-games-raid.service" "iscsi-target.service" ];
    path = [ pkgs.libvirt ];
    script = ''
      virsh start windows 2>/dev/null || true
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  # ── Packages ──
  environment.systemPackages = with pkgs; [ virt-manager git libvirt virtio-win swtpm jq ];
}