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
        1235  # llama-server (AI inference backend)
        1236  # llama-server-zephyr-3060ti
        1237  # llama-server-zephyr-3090 (Qwen3.6-35B-A3B)
      ];
      # Workaround: list merge is broken for this host. Ensure critical ports via nft rules.
      extraInputRules = ''
        tcp dport { 1235, 1236, 1237, 53317, 8080, 8888, 3900, 3901, 50000, 9100, 9400 } accept
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
      ];
      interfaces = {
        "eth0".allowedUDPPorts = [
          5353
          111
          2049
          20048
        ];
        "tailscale0".allowedTCPPorts = [
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
