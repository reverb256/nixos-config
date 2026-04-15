{ lib, ... }:
{
  networking = {
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        10250
        9100
        9105
        3334
        3900
        3901
      ];
      allowedTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472
      ];
    };
  };
}
