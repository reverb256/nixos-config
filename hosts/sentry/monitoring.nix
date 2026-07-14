{lib, ...}: {
  services = {
    gpu-exporters.enable = true;

    monitoring.system-tools = {
      enable = true;
      packageSet = "standard";
    };

    monitoring = {
      prometheus.enable = false; # Consolidated to nexus
      alertmanager.enable = false; # Consolidated to nexus
      alert-webhook.enable = false; # Consolidated to nexus
      alertmanager.email.enable = false;

      node-exporter.enable = true;
      smart-exporter.enable = true;
    };

    mining-exporter.enable = true;

    xmrig-metrics = {
      enable = true;
      targets = [
        "127.0.0.1:8081"
        "127.0.0.1:8083"
      ];
      interval = 30;
    };
  };

  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [9100];
}