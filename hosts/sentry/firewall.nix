{ lib, ... }:
{
  networking = {
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        22
        10250
        1235
        3100
        3900
        3901
        9100
      ];
      allowedTCPPortRanges = lib.mkOptionDefault [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472
      ];
      interfaces."enp7s0".allowedTCPPorts = [ 3100 ];
    };
  };
}
