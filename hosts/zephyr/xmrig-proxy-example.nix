_: {
  services.xmrig-proxy = {
    enable = true;

    config = builtins.toJSON {
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

      api = {
        port = 8081;
        restricted = true;
        token = "CHANGE_THIS_TO_SECURE_RANDOM_TOKEN";
      };

      log = {
        level = 5;
      };
    };

    listenPort = 3333;
    apiPort = 8081;

    services.prometheus.exporters.xmrig-proxy.enable = true;
  };
}
