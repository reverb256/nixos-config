rec {
  # Shared cluster constants — single source of truth for BOTH
  # K8s module evaluation (imported by kubernetes/default.nix) and
  # NixOS options (imported by modules/network-constants.nix for defaults).
  # Edit here to change subnet, VIP, API port, or cluster DNS IP.

  subnet = "10.1.1.0/24";
  podCidr = "10.42.0.0/16";

  zephyrIp = "10.1.1.110";
  nexusIp = "10.1.1.120";
  forgeIp = "10.1.1.130";
  sentryIp = "10.1.1.140";

  hosts = {
    zephyr.ip = zephyrIp;
    nexus.ip = nexusIp;
    forge.ip = forgeIp;
    sentry.ip = sentryIp;
  };

  kubernetes = {
    gatewayUrl = "http://${zephyrIp}:8080/v1"; # zephyr AI Inference Gateway
    vip = "10.1.1.100";
    apiPort = 6443;
    clusterDnsIP = "10.43.0.10";
  };

  # Import service-ports for use in other modules
  nodePorts = import ./service-ports.nix;

  # Per-host xmrig CPU miner toggles (default: all enabled)
  # Set to false to exclude a host's miner from the manifest entirely.
  mining = {
    enableZephyr = true;
    enableNexus = true;
    enableSentry = true;

    # GPU miner toggles
    enableGpuForgeNvidia0 = true;
    enableGpuForgeNvidia1 = true;
    enableGpuForgeAmd0 = true;
    enableGpuForgeAmd1 = true;
    enableGpuZephyr = false; # 3060Ti reserved for AI inference

    # Scheduled scaling (CronJobs). Set schedule to "" to disable.
    # Cron format: "minute hour day month weekday" (UTC)
    # Example: scale down at 9am UTC weekdays, scale up at 6pm UTC
    scaleDown = {
      schedule = "0 9 * * 1-5"; # Mon-Fri 09:00 UTC
      replicas = 0;
    };
    scaleUp = {
      schedule = "0 18 * * *"; # Every day 18:00 UTC
      replicas = 1;
    };
  };
}
