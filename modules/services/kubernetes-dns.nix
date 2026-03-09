# Configure Kubernetes DNS to use host Unbound at 10.1.1.110
{...}: {
  # Configure kubelet to use host's Unbound
  services.kubernetes.kubelet.extraConfig = lib.mkForce ''
    --cluster-dns=10.1.1.110
    --cluster-domain=cluster.local
  '';

  # Configure cluster DNS
  services.kubernetes.kubelet.clusterDomain = "cluster.local";
}
