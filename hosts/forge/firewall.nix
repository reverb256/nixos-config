{lib, ...}: {
  networking = {
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        10250
        9105
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
        # Source-restrict monitoring + inference to LAN + pod CIDR
        ip saddr { 10.42.0.0/16, 10.1.1.0/24 } tcp dport { 9100, 9101, 9102, 9400, 3334, 3900, 3901 } accept
        ip saddr { 10.42.0.0/16, 10.1.1.0/24 } tcp dport { 8002, 8003 } accept
        ip saddr { 10.42.0.0/16, 10.1.1.0/24 } tcp dport 22000 accept
      '';
    };
  };
}
