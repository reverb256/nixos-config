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
          # generate_node_acls = 1 → target accepts ANY initiator (incl. the
          # libvirt/QEMU session that owns the E: virtio disk). This is a
          # single-host trusted LAN target (10.1.1.0/24 only), so demo-mode
          # ACLs are acceptable and eliminate the fragile per-IQN whitelist
          # that broke E: every reboot when the guest initiator name drifted.
          attributes = { authentication = 0; generate_node_acls = 1; demo_mode_write_protect = 0; demo_mode_discovery = 1; };
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
      virsh start krash3-vm 2>/dev/null || true
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  # ── Runtime files ────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "f /var/lib/libvirt/images/c.raw 0640 root kvm - -"
    "L+ /run/secrets/k3s-cluster-token - - - - /persistent/etc/k3s-cluster-token"
  ];

  # ── E: drive watchdog ───────────────────────────────────
  # Verifies from INSIDE the guest that E: is mounted/healthy. If not, it
  # re-attach the iSCSI virtio disk to the running domain and restarts the
  # target backstore. This makes E: self-healing across guest reboots and
  # target restarts — the permanent fix for the recurring E:-missing failure.
  systemd.services.e-drive-watchdog = {
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" "iscsi-target.service" ];
    path = [ pkgs.libvirt pkgs.qemu ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      DOM="krash3-vm"
      # Is the domain even running?
      if ! virsh domstate "$DOM" 2>/dev/null | grep -q running; then
        virsh start "$DOM" 2>/dev/null || true
        sleep 15
      fi
      # Probe the guest for E: via qemu-agent
      check() {
        virsh qemu-agent-command "$DOM" '{"execute":"guest-exec","arguments":{"path":"C:\\Windows\\System32\\cmd.exe","arg":["/c","powershell -command \"Get-Volume -DriveLetter E -ErrorAction SilentlyContinue | Select -ExpandProperty HealthStatus\""],"capture-output":true}}' 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '.return' 2>/dev/null
      }
      OUT=$(check)
      if echo "$OUT" | grep -qi "Healthy"; then
        echo "E: healthy — no action needed"
        exit 0
      fi
      echo "E: NOT healthy (got: $OUT) — attempting recovery"
      # Re-attach the iSCSI virtio disk if missing from the running domain
      if ! virsh dumpxml "$DOM" 2>/dev/null | grep -q "iqn.2025-06.lan.krash3:games"; then
        virsh attach-disk "$DOM" --type network --source-url iscsi://192.168.122.1:3260/iqn.2025-06.lan.krash3:games/0 --target vdb --persistent 2>&1 || true
      fi
      # Restart target backstore to clear any stale session
      systemctl restart iscsi-target.service 2>/dev/null || true
      sleep 5
      # Final probe
      OUT2=$(check)
      if echo "$OUT2" | grep -qi "Healthy"; then
        echo "E: recovered — healthy"
        exit 0
      else
        echo "E: STILL NOT HEALTHY after recovery: $OUT2"
        exit 1
      fi
    '';
  };

  systemd.timers.e-drive-watchdog = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "60s";
      OnUnitActiveSec = "300s";
      Unit = "e-drive-watchdog.service";
    };
  };

  # ── Packages ─────────────────────────────────────────────
  environment.systemPackages = with pkgs; [ virt-manager git libvirt virtio-win swtpm jq ];
}
