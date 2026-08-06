{
  config,
  pkgs,
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
          name = "zephyr-3060ti";
          devices = "0";
          gpuId = 0;
          powerLimit = 120;
          apiPort = 21553;
          exporterPort = 9101;
        }
        {
          name = "zephyr-3090";
          devices = "1";
          gpuId = 1;
          powerLimit = 250;
          apiPort = 21554;
          exporterPort = 9102;
        }
      ];
    };

    # lpminer disabled: Krig now owns zephyr's two GPUs (same PRL pool).
    # Running both would fight for the devices.
    lpminer.enable = lib.mkForce false;
    gaming-detection.enable = lib.mkForce false;
    gpu-profile-manager.enable = lib.mkForce false;
  };
}
