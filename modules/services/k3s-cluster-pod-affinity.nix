{
  config,
  pkgs,
  lib,
  ...
}: {
  # Enable pod affinity rules on all k3s control-plane nodes
  services.k3s-pod-affinity.enable = config.services.k3s-cluster.enable;
}