{
  config,
  lib,
  ...
}: let
  cluster = config.networking.cluster;
in {
  services = {
    krig = {
      enable = true;
      wallet = "krxXVNVMM7";
      pool = "stratum+ssl://prl-us.kryptex.network:8048";
      instances = [
        {
          name = "nexus-3060ti";
          devices = "0";
          gpuId = 0;
          powerLimit = 120;
          apiPort = 21551;
          exporterPort = 9101;
        }
      ];
    };

    lpminer.enable = lib.mkForce false;
    gaming-detection.enable = lib.mkForce false;
  };
}
