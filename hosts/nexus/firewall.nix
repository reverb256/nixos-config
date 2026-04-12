# Nexus Firewall Configuration
# Control plane + storage node - Kubelet, Garage S3, AI inference, NodePort range
{ lib, ... }:
{
  networking = {
    firewall = {
      # Nexus-specific firewall rules (merge with cluster defaults)
      # NOTE: allowedTCPPorts with mkOptionDefault inside mkMerge blocks
      # has a known merge issue. Use extraInputRules for reliable access.
      extraInputRules = lib.mkAfter ''
        # Haven chat server
        tcp dport 3000 accept
      '';
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
