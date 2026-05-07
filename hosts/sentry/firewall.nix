{lib, ...}: {
  networking = {
    firewall = {
      extraInputRules = lib.mkAfter ''
        tcp dport { 1235, 3100, 3900, 3901, 9100 } accept
      '';
      allowedTCPPortRanges = lib.mkOptionDefault [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472
      ];
      interfaces."eth0".allowedTCPPorts = [3100];
    };
  };
}
