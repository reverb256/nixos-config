_: {
  services.mining-proxy = {
    enable = true;

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

    listenPort = 3334;
    apiPort = 8082;
  };
}
