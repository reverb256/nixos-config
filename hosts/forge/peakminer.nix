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
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = cluster.hosts.forge.ip;
    };

    peakminer = {
      enable = true;
      wallet = "krxXVNVMM7";
      pools = ["stratum+tcp://prl-us.kryptex.network:7048"];
      instances = [
        {
          name = "forge-4060-workload";
          devices = "0,1";
          gpuId = 0;
          powerLimit = 90;
          tempStop = 75;
          fanTarget = 65;
          fanMin = 30;
          fanMax = 100;
          apiPort = 21550;
        }
      ];
      exporterInstances = [
        { instanceName = "forge-4060-workload"; apiPort = 21550; exporterPort = 9101; }
      ];
    };

    srbminer.enable = lib.mkForce false;
    gaming-detection.enable = lib.mkForce false;
  };
}
