{ config, lib, ... }:
{
  # Issue #246: Clock drift caused etcd leader election failures and
  # sentry-node deadlock. This module ensures chrony is configured for
  # consistent timekeeping across the cluster.
  services.chrony = {
    enable = true;
    servers = config.networking.timeServers;
    serverOption = "iburst trust";
    enableRTCTrimming = true;
    autotrimThreshold = 1.0;
    enableMemoryLocking = true;
    makestep = {
      enable = true;
      threshold = 0.1;
      limit = 1;
    };
    directory = "/var/lib/chrony";
    extraConfig = ''
      logchange 0.1
      logdir /var/log/chrony
    '';
  };
}
