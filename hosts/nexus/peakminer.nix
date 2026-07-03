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
      nodeName = "nexus";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/persistent/etc/k3s-cluster-token";
      nodeIP = cluster.hosts.nexus.ip;
      flannelIface = "eth0";
    };

    peakminer = {
      enable = true;
      wallet = "krxXVNVMM7";
      pools = ["stratum+tcp://prl.kryptex.network:7048"];
      instances = [
        {
          name = "nexus-3060ti";
          devices = "0";
          gpuId = 0;
          powerLimit = 120;
          tempStop = 72;
          fanTarget = 65;
          fanMin = 30;
          fanMax = 100;
          apiPort = 21551;
        }
      ];
      exporterInstances = [
        { instanceName = "nexus-3060ti"; apiPort = 21551; exporterPort = 9101; }
      ];
    };

    lpminer.enable = lib.mkForce false;
    gaming-detection.enable = lib.mkForce false;
  };
}
