{
  lib,
  ...
}: {
  services.peakminer = {
    enable = true;
    wallet = "krxXVNVMM7";
    password = "x";
    pools = [
      "stratum+tcp://prl-us.kryptex.network:7048"
      "stratum+tcp://prl.kryptex.network:7048"
    ];
    instances = [
      {
        name = "zephyr-3060ti";
        gpuName = "RTX 3060 Ti";
        devices = "0";
        gpuId = 0;
        powerLimit = 120;
        apiPort = 21553;
      }
      {
        name = "zephyr-3090";
        gpuName = "RTX 3090";
        devices = "1";
        gpuId = 1;
        powerLimit = 250;
        apiPort = 21554;
      }
    ];
  };

  services.gaming-detection.enable = lib.mkForce false;
  services.gpu-profile-manager.enable = lib.mkForce false;
}
