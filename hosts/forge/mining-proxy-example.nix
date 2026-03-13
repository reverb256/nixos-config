# Example Mining Proxy Configuration
# For multi-algorithm support (GPU + CPU)
{
  config,
  pkgs,
  lib,
  ...
}: {
  services.mining-proxy = {
    enable = true;

    # Pool failover configuration
    # IMPORTANT: Replace URLs and configure your own pool credentials
    pools = [
      {
        name = "your-pool-primary";
        url = "stratum+ssl://your-pool-url:port";
        priority = 1;
        weight = 100;
      }
      {
        name = "your-pool-backup";
        url = "stratum+ssl://your-backup-pool-url:port";
        priority = 2;
        weight = 50;
      }
    ];

    # GPU workers (Forge, Zephyr, Nexus)
    # Configure worker IDs and passwords for your mining setup
    workers = [
      {
        id = "forge-nvidia-gpu0";
        password = "YOUR_WORKER_PASSWORD";
      }
      {
        id = "forge-nvidia-gpu1";
        password = "YOUR_WORKER_PASSWORD";
      }
      {
        id = "forge-amd-gpu0";
        password = "YOUR_WORKER_PASSWORD";
      }
      {
        id = "forge-amd-gpu1";
        password = "YOUR_WORKER_PASSWORD";
      }
      {
        id = "zephyr-3090";
        password = "YOUR_WORKER_PASSWORD";
      }
      {
        id = "nexus-3060ti";
        password = "YOUR_WORKER_PASSWORD";
      }
    ];

    listenPort = 3334; # Different from xmrig-proxy
    apiPort = 8082;
  };
}
