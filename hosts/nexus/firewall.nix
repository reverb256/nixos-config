# Nexus Firewall Configuration
# Control plane + storage node - Kubelet, Garage S3, AI inference, NodePort range
{ lib, ... }:
{
  networking = {
    # Nexus-specific firewall rules (in addition to cluster defaults)
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        10250 # Kubelet API
        3900 # Garage S3 API
        3901 # Garage RPC
        8080 # llama-server for autoresearch LLM evaluation
        9100 # Prometheus node-exporter
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
