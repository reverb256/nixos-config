{
  config,
  pkgs,
  lib,
  ...
}:
let
  cluster = config.networking.cluster;
in {
  services = {
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "agent";
      nodeName = "zephyr";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = cluster.hosts.zephyr.ip;
    };

    peakminer = {
      enable = true;
      wallet = "krxXVNVMM7";
      pools = ["stratum+tcp://prl.kryptex.network:7048"];
      exporterInstances = [
        { instanceName = "zephyr-3060ti"; apiPort = 21553; exporterPort = 9101; }
        { instanceName = "zephyr-3090";   apiPort = 21554; exporterPort = 9102; }
      ];
      instances = [
        {
          name = "zephyr-3060ti";
          devices = "0";
          gpuId = 0;
          powerLimit = 120;
          tempStop = 80;
          fanTarget = 65;
          fanMin = 30;
          fanMax = 100;
          apiPort = 21553;
        }
        {
          name = "zephyr-3090";
          devices = "1";
          gpuId = 1;
          powerLimit = 250;
          tempStop = 80;
          fanTarget = 65;
          fanMin = 30;
          fanMax = 100;
          apiPort = 21554;
        }
      ];
    };

    gaming-detection.enable = lib.mkForce false;
    gpu-profile-manager.enable = lib.mkForce false;
    lpminer.enable = lib.mkForce false;
    srbminer.enable = lib.mkForce false;
  };
}
