{lib, ...}: {
  networking = {
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        80 # HTTP→HTTPS redirect
        9757
        18789
        18790
        19898
        3333
        8080
        8083
        53317
        8888
        3900
        3901
        50000
        6443
        2379
        2380
        10250
        179
        5473
        9100
        9101 # Hermes agent Prometheus exporter
        1235 # llama-server (Qwen3.6-27B Dense + DFlash)
        # Ubisoft Connect / Ghost Recon Wildlands
        14000
        14008
        14020
        14021
        14022
        14023
        14024
      ];
      # Workaround: list merge is broken for this host. Ensure critical ports via nft rules.
      extraInputRules = ''
        tcp dport { 32000, 80, 443, 1235, 1237, 53317, 8080, 8040, 8041, 8888, 3900, 3901, 50000, 9100, 9101, 9400, 14000, 14008, 14020, 14021, 14022, 14023, 14024 } accept
        udp dport { 3074, 3075, 3076, 3077, 3078, 3079, 3080, 3081, 3082, 3083, 27000, 27001, 27002, 27003, 27004, 27005, 27006, 27007, 27008, 27009, 27010, 27011, 27012, 27013, 27014, 27015, 27016, 27017, 27018, 27019, 27020, 27021, 27022, 27023, 27024, 27025, 27026, 27027, 27028, 27029, 27030, 27031, 27032 } accept
      '';
      allowedUDPPorts = lib.mkOptionDefault [
        9757
        9758
        9759
        27031
        27036
        9947
        53317
        8472
        4789
        # Ghost Recon Wildlands / Steam matchmaking
        3074
        3075
        3076
        3077
        3078
        3079
        3080
        3081
        3082
        3083
        27000
        27001
        27002
        27003
        27004
        27005
        27006
        27007
        27008
        27009
        27010
        27011
        27012
        27013
        27014
        27015
        27016
        27017
        27018
        27019
        27020
        27021
        27022
        27023
        27024
        27025
        27026
        27027
        27028
        27029
        27030
        27031
        27032
      ];
      interfaces = {
        "eth0".allowedUDPPorts = [
          5353
          111
          2049
          20048
        ];
        "tailscale0".allowedTCPPorts = lib.mkOptionDefault [
          443
          9002
          18789
          18790
        ];
        "eth0".allowedTCPPorts = [
          111
          2049
          20048
        ];
      };
    };
  };
}
