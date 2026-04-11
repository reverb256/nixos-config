# Zephyr Firewall Configuration
# Host-specific firewall rules in addition to cluster defaults
# Ports are merged with modules providing their own rules (monitoring, etc.)
{ lib, ... }:
{
  networking = {
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        9757 # WiVRn main port
        18789 # Steam Remote Play
        18790 # Steam Remote Play (secondary)
        19898 # Moonlight/GameStream AND Spacebot Web UI
        3333 # XMRig stratum proxy (for GPU miners)
        8080 # AI Inference Gateway
        8083 # Llamafile standalone LLM service
        53317 # LocalSend (file sharing)
        8888 # CFSSL CA API server
        3900 # Garage S3 API
        3901 # Garage RPC
        50000 # Nix binary cache server
        6443 # k3s API server
        2379 # etcd client
        2380 # etcd peer
        10250 # Kubelet API
        179 # Calico BGP
        5473 # Calico Typha
        9100 # Prometheus node-exporter
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        9757 # WiVRn
        9758 # WiVRn
        9759 # WiVRn
        27031 # Steam UDP
        27036 # Steam UDP
        9947 # WiVRn
        53317 # LocalSend (multicast discovery)
        8472 # VXLAN (Flannel/Calico)
        4789 # VXLAN (Calico)
      ];
      interfaces = {
        # mDNS restricted to LAN interface only (not 0.0.0.0)
        "enp38s0".allowedUDPPorts = [
          5353
          111
          2049
          20048
        ];
        "tailscale0".allowedTCPPorts = [
          18789
          18790
        ];
        # NFS server - allow local network only
        "enp38s0".allowedTCPPorts = [
          111 # rpcbind
          2049 # nfs
          20048 # mountd
        ];
      };
    };
  };
}
