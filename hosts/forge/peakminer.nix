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
      role = "server";
      clusterInit = false;
      nodeName = "forge";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = cluster.hosts.forge.ip;
    };

    peakminer = {
      enable = true;
      wallet = "krxXVNVMM7";
      pools = ["stratum+tcp://prl.kryptex.network:7048"];
      instances = [
        {
          name = "forge-4060-0";
          devices = "0";
          gpuId = 0;
          powerLimit = 118;
          tempStop = 72;
          fanTarget = 65;
          fanMin = 30;
          fanMax = 100;
          apiPort = 21550;
          proxyPort = 21540;
        }
        {
          name = "forge-4060-1";
          devices = "1";
          gpuId = 1;
          powerLimit = 118;
          tempStop = 72;
          fanTarget = 65;
          fanMin = 30;
          fanMax = 100;
          apiPort = 21552;
          proxyPort = 21541;
        }
      ];
    };

    srbminer.enable = lib.mkForce false;
    gaming-detection.enable = lib.mkForce false;
  };
}