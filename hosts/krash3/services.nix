{ config, pkgs, lib, ... }:
let
  params = import ./params.nix;
  inherit (params) vm;
in {
  # ── Unbound DNS ─────────────────────────────────────────
  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [ "127.0.0.1" "::1" "10.1.1.150" ];
        access-control = [ "127.0.0.0/8 allow" "10.1.1.0/24 allow" "::1 allow" ];
        private-domain = "lan";
        local-zone = [ "lan. static" ];
        local-data = [
          # Services (Caddy-proxied via VIP 10.1.1.100 for HA)
          ''"maplespike.lan. A 10.1.1.100"''
          ''"api.maplespike.lan. A 10.1.1.100"''
          ''"searxng.lan. A 10.1.1.100"''
          ''"search.lan. A 10.1.1.100"''
          ''"vane.lan. A 10.1.1.100"''
          ''"haven.lan. A 10.1.1.100"''
          ''"ai-inference.lan. A 10.1.1.100"''
          ''"auth.lan. A 10.1.1.100"''
          ''"grafana.lan. A 10.1.1.100"''
          ''"n8n.lan. A 10.1.1.100"''
          ''"gitea.lan. A 10.1.1.100"''
          # Host records (direct IPs)
          ''"nexus.lan. A 10.1.1.120"''
          ''"zephyr.lan. A 10.1.1.110"''
          ''"forge.lan. A 10.1.1.130"''
          ''"sentry.lan. A 10.1.1.140"''
          # Infrastructure
          ''"k3s-api.lan. A 10.1.1.100"''
        ];
      };
      forward-zone = [{
        name = ".";
        forward-addr = [ "10.1.1.100" ];
      }];
    };
  };

  # ── iSCSI target ────────────────────────────────────────
  # Provides the E: drive to the Windows VM via LIO kernel target
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
          attributes = { authentication = 0; generate_node_acls = 0; demo_mode_write_protect = 1; demo_mode_discovery = 1; };
          node_acls = [{
            node_wwn = "iqn.1991-05.com.microsoft:krash3-vm";
            mapped_luns = [{
              tpg_lun = 0;
              write_protect = false;
            }];
          } {
            node_wwn = "iqn.1991-05.com.microsoft:desktop-a0cvoc1";
            mapped_luns = [{
              tpg_lun = 0;
              write_protect = false;
            }];
          }];
        }];
      }];
    };
  };
  # Ordering: wait for RAID to assemble before restoring iSCSI target
  systemd.services.iscsi-target = {
    after = [ "assemble-games-raid.service" ];
    requires = [ "assemble-games-raid.service" ];
    serviceConfig = {
      # Wait for /dev/md0p1 to appear before running rtslib-fb restore
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $$(seq 1 30); do if [ -b /dev/md0p1 ]; then exit 0; fi; sleep 2; done; exit 1'";
      # Prevent rtslib-fb clear from destroying active iSCSI sessions on service stop
      ExecStop = lib.mkForce [ "${pkgs.coreutils}/bin/true" ];
      # ACLs are now declared in services.target.config above — no need for targetcli calls
    };
    # Don't restart on config changes — existing sessions must survive rebuilds
    stopIfChanged = false;
  };

  # ── Samba ────────────────────────────────────────────────
  services.samba = {
    enable = true; openFirewall = lib.mkForce false;
    settings = {
      global = {
        workgroup = "WORKGROUP"; "server string" = "krash3"; "netbios name" = "krash3";
        security = "user"; "map to guest" = "Bad User"; "guest account" = "nobody";
      };
    };
  };

  # ── k3s cluster agent ────────────────────────────────────
  services.k3s-cluster = {
    enable = true;
    nvidia.enable = true;
    role = "agent";
    nodeName = "krash3";
    serverAddr = "https://${config.networking.cluster.kubernetes.vip}:${toString config.networking.cluster.kubernetes.apiPort}";
    tokenFile = "/run/secrets/k3s-cluster-token";
    nodeIP = config.networking.cluster.hosts.krash3.ip;
    flannelIface = "enp7s0";
  };
  services.k3s-pod-affinity.enable = lib.mkForce false;

  # ── VM autostart ─────────────────────────────────────────
  systemd.services.libvirt-autostart-windows = {
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" "assemble-games-raid.service" "iscsi-target.service" ];
    path = [ pkgs.libvirt ];
    script = ''
      virsh start windows 2>/dev/null || true
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  # ── Runtime files ────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "f /var/lib/libvirt/images/c.raw 0640 root kvm - -"
    "L+ /run/secrets/k3s-cluster-token - - - - /persistent/etc/k3s-cluster-token"
  ];

  # ── Packages ─────────────────────────────────────────────
  environment.systemPackages = with pkgs; [ virt-manager git libvirt virtio-win swtpm jq ];
}
