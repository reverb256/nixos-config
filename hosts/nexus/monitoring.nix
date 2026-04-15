{ lib, ... }:
{
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  services = {
    gpu-exporters = {
      enable = true;
      nvidia.enable = true;
    };

    monitoring.system-tools = {
      enable = true;
      packageSet = "standard";
    };

    monitoring.node-exporter = {
      enable = true;
      listenAddress = "0.0.0.0";
    };

    monitoring.smart-exporter.enable = true;

    mining-exporter.enable = true;


    xmrig-metrics = {
      enable = true;
      targets = [
        "127.0.0.1:8082"
        "127.0.0.1:8083"
      ];
      interval = 30;
    };
  };

  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ 9100 ];
}
