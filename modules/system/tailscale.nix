{lib, pkgs, ...}:
with lib; {
  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraSetFlags = [
      "--ssh"
      "--accept-dns=false"
      "--advertise-exit-node"
      "--operator=j_kro"
    ];
    extraUpFlags = [
      "--reset"
    ];
  };

  systemd.services.tailscaled = {
    environment = {
      TS_LOG_LEVEL = "info";
    };
  };

  # Enable IP forwarding for exit node functionality
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Enable IP forwarding persistently and fix UDP GRO
  systemd.services.tailscale-ip-fix = {
    description = "Configure IP forwarding and UDP GRO for Tailscale exit node";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig.Type = "oneshot";
    script = ''
      # Enable IP forwarding (in case sysctl doesn't apply immediately)
      echo 1 > /proc/sys/net/ipv4/ip_forward
      echo 1 > /proc/sys/net/ipv6/conf/all/forwarding

      # Fix UDP GRO forwarding on eth0
      ${pkgs.ethtool}/bin/ethtool -K eth0 rx-udp-gro-forwarding on || true
    '';
  };
}
