{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  # ── Fix: Declarative static IP configuration via systemd-networkd ──
  # NetworkManager is disabled in favor of networkd for reliable static IP.
  # This prevents the "reboot loses IP" issue.

  networking.networkmanager.enable = lib.mkForce false;

  # Use Unbound as DNS resolver (not systemd-resolved)
  services.resolved.enable = lib.mkForce false;

  systemd.network = {
    enable = true;

    # Keep original interface names (prevent udev renaming to enp7s0)
    links."10-keep-names" = {
      matchConfig.OriginalName = "*";
      linkConfig.NamePolicy = "keep";
    };

    # Static IP on primary wired interface (eth0)
    networks."30-wired" = {
      matchConfig.Name = "eth0";
      address = [ "10.1.1.120/24" ];
      gateway = "10.1.1.1";
      dns = ["127.0.0.1"];
      routes = [{ routeConfig.Gateway = "10.1.1.1"; }];
      networkConfig.IPv6AcceptRA = false;
      linkConfig.RequiredForOnline = "routable";
    };
  };

  # Fix: Update interface references from enp7s0 to eth0 for consistency
  # The keep-names policy preserves eth0, so all services must reference eth0
  networking.hostName = "nexus";
  networking.search = ["lan" "cluster.local" "taila21e09.ts.net"];
  networking.nameservers = ["127.0.0.1"];

  # IPv6 disabled on physical interface (keep loopback ::1 for local DNS)
  boot.kernel.sysctl = {
    "net.ipv6.conf.eth0.disable_ipv6" = 1;
  };

  # Keepalived VRRP and K3s Flannel use eth0 (already correct in services.nix)
  # No changes needed there - services.nix already references eth0
}