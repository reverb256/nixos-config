{lib, ...}: {
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
      extraInputRules = ''
        ip saddr { 10.42.0.0/16, 10.1.1.0/24 } tcp dport { 9100, 9400 } accept
      '';
    };
  };
}
