# Sentry Firewall Configuration
# Monitoring server - SSH, Kubelet, Loki, Garage S3, Prometheus node-exporter
{ lib, ... }:
{
  networking = {
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        22
        10250
        3100
        3900
        3901
        9100 # Prometheus node-exporter
      ];
      allowedTCPPortRanges = lib.mkOptionDefault [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472 # VXLAN (Flannel or Calico)
      ];
      # Open Loki port on main interface for cluster access
      interfaces."enp7s0".allowedTCPPorts = [ 3100 ];
    };
  };
}
