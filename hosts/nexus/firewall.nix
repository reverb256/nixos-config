{ lib, ... }:
{
  networking = {
    firewall = {
      extraInputRules = lib.mkAfter ''
        tcp dport 3000 accept
      '';
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
