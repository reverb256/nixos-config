{
  # Shared cluster constants — single source of truth for K8s modules.
  # Network-constants.nix mirrors these as NixOS options via config.networking.cluster.
  # If you change something here, update network-constants.nix too.

  subnet = "10.1.1.0/24";
  podCidr = "10.244.0.0/16";

  hosts = {
    zephyr.ip = "10.1.1.110";
    nexus.ip = "10.1.1.120";
    forge.ip = "10.1.1.130";
    sentry.ip = "10.1.1.140";
  };

  kubernetes = {
    vip = "10.1.1.100";
    apiPort = 6443;
    clusterDnsIP = "10.0.0.10";
  };
}
