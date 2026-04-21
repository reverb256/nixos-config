{ lib, ... }:
{
  networking = {
    firewall = {
      extraInputRules = lib.mkAfter ''
        tcp dport { 3000, 6333, 6334, 8080, 8642, 8643, 8650, 8787, 9119, 9100, 9400 } accept
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
