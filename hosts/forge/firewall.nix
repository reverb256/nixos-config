# Forge Firewall Configuration
# GPU mining rig - Kubelet, GPU proxy, Garage S3, K8s NodePort range
{ lib, ... }:
{
  networking = {
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        10250 # Kubelet API
        3334 # gpu-proxy-cpp (centralized proxy for cluster)
        3900 # Garage S3 API (if needed)
        3901 # Garage RPC (if needed)
      ];
      allowedTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472 # VXLAN (Flannel or Calico)
      ];
    };
  };
}
