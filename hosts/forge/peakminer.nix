{lib, ...}: {
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
        name = "forge-4060-0";
        gpuName = "RTX 4060";
        devices = "0";
        gpuId = 0;
        powerLimit = 118;
        apiPort = 21550;
      }
      {
        name = "forge-4060-1";
        gpuName = "RTX 4060";
        devices = "1";
        gpuId = 1;
        powerLimit = 118;
        apiPort = 21552;
      }
    ];
  };

  services.gaming-detection.enable = lib.mkForce false;
}
