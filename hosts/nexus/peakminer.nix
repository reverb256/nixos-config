{lib, ...}: {
  services.peakminer = {
    enable = false;
    wallet = "krxXVNVMM7";
    password = "x";
    pools = [
      "stratum+tcp://prl-us.kryptex.network:7048"
      "stratum+tcp://prl.kryptex.network:7048"
    ];
    instances = [
      {
        name = "nexus-3060ti";
        gpuName = "RTX 3060 Ti";
        devices = "0";
        gpuId = 0;
        powerLimit = 120;
        apiPort = 21551;
      }
    ];
  };

  services.gaming-detection.enable = lib.mkForce false;
}
