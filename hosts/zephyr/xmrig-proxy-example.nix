# Example XMRig Proxy Configuration
# For Zephyr - Centralized CPU mining proxy for cluster
{
  config,
  pkgs,
  lib,
  ...
}: {
  services.xmrig-proxy = {
    enable = true;

    # Configuration for the cluster
    # IMPORTANT: Configure your own pool credentials below
    config = builtins.toJSON {
      # Pools with failover priority
      pools = [
        {
          id = "your-pool-primary";
          url = "your-pool-url:port";
          user = "YOUR_WALLET_ADDRESS.worker-name";
          pass = "YOUR_POOL_PASSWORD";
          tls = true;
          keepalive = true;
          priority = 1;
        }
        {
          id = "your-pool-backup";
          url = "your-backup-pool-url:port";
          user = "YOUR_WALLET_ADDRESS.worker-name";
          pass = "YOUR_POOL_PASSWORD";
          tls = false;
          priority = 2;
        }
      ];

      # Workers (CPU miners)
      workers = [
        {
          id = "zephyr-cpu";
          password = "YOUR_WORKER_PASSWORD";
        }
        {
          id = "nexus-cpu";
          password = "YOUR_WORKER_PASSWORD";
        }
        {
          id = "sentry-cpu";
          password = "YOUR_WORKER_PASSWORD";
        }
      ];

      # API for monitoring
      api = {
        port = 8081;
        restricted = true;
        token = "CHANGE_THIS_TO_SECURE_RANDOM_TOKEN";
      };

      # Logging
      log = {
        level = 5; # Info level
      };
    };

    listenPort = 3333;
    apiPort = 8081;

    # Monitoring integration
    services.prometheus.exporters.xmrig-proxy.enable = true;
  };
}
