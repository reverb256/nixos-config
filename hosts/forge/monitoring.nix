_: {
  services = {
    gpu-exporters.enable = true;

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
  };
}
