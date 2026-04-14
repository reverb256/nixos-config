{ lib, ... }:
{
  networking = {
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
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
      ];
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
      ];
      interfaces = {
        "enp38s0".allowedUDPPorts = [
          5353
          111
          2049
          20048
        ];
        "tailscale0".allowedTCPPorts = [
          18789
          18790
        ];
        "enp38s0".allowedTCPPorts = [
          111
          2049
          20048
        ];
      };
    };
  };
}
