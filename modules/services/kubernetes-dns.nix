# Configure Kubernetes DNS to use host Unbound at 10.1.1.110
{config, ...}: {
  # Configure kubelet to use host's Unbound
  # Note: Use mkOptionDefault to preserve anonymous authentication from kubernetes.nix
  services.kubernetes.kubelet.clusterDns = lib.mkOptionDefault [ "10.1.1.110" ];

  # Configure cluster DNS
  services.kubernetes.kubelet.clusterDomain = "cluster.local";
}
