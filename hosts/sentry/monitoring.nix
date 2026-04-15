{ lib, ... }:
{
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  services = {
    gpu-exporters = {
      enable = true;
      amd.enable = true;
    };

    monitoring.system-tools = {
      enable = true;
      packageSet = "standard";
    };

    monitoring = {
      prometheus.enable = true;
      grafana.enable = true;
      alertmanager.enable = true;
      alert-webhook.enable = true;
      alertmanager.email.enable = false;
      loki = {
        enable = true;
        listenAddress = "0.0.0.0";
        dataDir = "/storage/loki";
      };

      node-exporter.enable = true;
      smart-exporter.enable = true;

    };


    mining-exporter.enable = true;

    self-healing-alerts = {
      enable = true;
      monitoredServices = [
        "kubelet"
        "kube-apiserver"
        "containerd"
        "etcd"
        "keepalived"
      ];
      enableCircuitBreakerAlerts = false;
      enableVIPFailoverAlerts = true;
      enableResourceAlerts = true;
      memoryThreshold = 90;
      diskThreshold = 90;
    };

    xmrig-metrics = {
      enable = true;
      targets = [
        "127.0.0.1:8081"
        "127.0.0.1:8083"
      ];
      interval = 30;
    };
  };

  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ 9100 ];
}
