{lib, ...}: {
  networking = {
    firewall = {
      extraInputRules = lib.mkAfter ''
        # Source-restrict exposed ports to LAN + pod CIDR
        ip saddr { 10.1.1.0/24, 10.42.0.0/16 } tcp dport { 1235, 4180, 3100, 3900, 3901, 9100, 8001, 8002, 8003 } accept
        ip saddr { 10.1.1.0/24, 10.42.0.0/16 } tcp dport 22000 accept
        ip saddr { 10.1.1.0/24, 10.42.0.0/16 } tcp dport 11434 accept
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
      interfaces."eth0".allowedTCPPorts = lib.mkOptionDefault [3100];
    };
  };
}
