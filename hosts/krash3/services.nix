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

  # ── E: drive ────────────────────────────────────────────
  # E: is now a DIRECT virtio-blk disk on /dev/md0p1 (see declarative-vm.nix),
  # NOT an iSCSI target. No target service means rebuilds/reboots cannot kill
  # E: — it is available by construction as long as the RAID assembles.
  # The assemble-games-raid.service still runs (provides /dev/md0p1).

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
  # Define the domain from the declarative XML FIRST (so the running domain
  # always matches config), then start it. `virsh define` is idempotent.
  systemd.services.libvirt-autostart-windows = {
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" "assemble-games-raid.service" ];
    path = [ pkgs.libvirt ];
    script = ''
      virsh define /etc/libvirt/qemu/krash3-vm.xml 2>/dev/null || true
      virsh start krash3-vm 2>/dev/null || true
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  # ── Guest-agent self-healing ───────────────────────────
  # The qemu-guest-agent inside Windows wedges / fails to auto-start, leaving
  # the org.qemu.guest_agent.0 channel disconnected after VM boot. This
  # oneshot does a best-effort heal: ping the agent; if wedged, restart the
  # Windows qemu-ga service once via bounded guest-exec. It MUST NOT block
  # host deploys — short timeout, single attempt, exit either way. The real
  # durable fix is the Windows qemu-ga service set to Automatic start
  # (one-time guest-side step); this just auto-recovers transient wedges.
  systemd.services.krash3-vm-agent-health = {
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirt-autostart-windows.service" ];
    path = [ pkgs.libvirt pkgs.jq ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 30;
    };
    script = ''
      export LIBVIRT_URI=qemu:///system
      DOM="krash3-vm"
      ping_agent() {
        out=$(sudo virsh qemu-agent-command "$DOM" '{"execute":"guest-ping"}' 2>/dev/null)
        echo "$out" | grep -q '"return"'
      }
      # Only act if the domain is actually running.
      sudo virsh domstate "$DOM" 2>/dev/null | grep -q running || { echo "guest not running, skip"; exit 0; }
      if ping_agent; then
        echo "guest-agent: healthy"
        exit 0
      fi
      echo "guest-agent: down — one-shot restart of Windows qemu-ga service"
      sudo virsh qemu-agent-command "$DOM" "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"C:\\\\Windows\\\\System32\\\\cmd.exe\",\"arg\":[\"/c\",\"net stop qemu-guest-agent & net start qemu-guest-agent\"],\"capture-output\":true}}" >/dev/null 2>&1 || true
      sleep 8
      if ping_agent; then
        echo "guest-agent: recovered"
      else
        echo "guest-agent: still down (Windows qemu-ga service likely not set to Automatic — set it once in guest)"
      fi
      # Exit 0 regardless: never block host deploys / switch.
      exit 0
    '';
  };

  # ── Runtime files ────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "f /var/lib/libvirt/images/c.raw 0640 root kvm - -"
    "L+ /run/secrets/k3s-cluster-token - - - - /persistent/etc/k3s-cluster-token"
  ];

  # ── E: drive watchdog ───────────────────────────────────
  # Verifies from INSIDE the guest that E: is mounted/healthy. Since E: is now
  # a direct virtio-blk disk on /dev/md0p1 (no iSCSI target), the only failure
  # mode is the disk not being attached to the running domain (e.g. after a
  # manual VM redefinition). Self-heals by re-attaching the block disk.
  systemd.services.e-drive-watchdog = {
    # NOTE: intentionally NOT in wantedBy — running this during switch causes
    # the switch to abort if the VM/hypervisor isn't ready yet. It runs via the
    # timer (e-drive-watchdog.timer) after boot, when the VM is up.
    after = [ "libvirtd.service" "assemble-games-raid.service" ];
    path = [ pkgs.libvirt pkgs.qemu ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      export LIBVIRT_URI=qemu:///system
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
      # Re-attach the block disk if missing from the running domain
      if ! virsh dumpxml "$DOM" 2>/dev/null | grep -q "vdb"; then
        virsh attach-disk "$DOM" --type block --source /dev/md0p1 --target vdb --persistent 2>&1 || true
      fi
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
