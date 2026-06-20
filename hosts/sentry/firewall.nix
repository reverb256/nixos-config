{lib, ...}: {
  networking = {
    firewall = {
      extraInputRules = lib.mkAfter ''
        tcp dport { 1235, 4180, 3100, 3900, 3901, 8001, 8002, 8003, 9100 } accept
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
      interfaces."eth0".allowedTCPPorts = [3100 8001 8002 8003];
    };
  };
}
