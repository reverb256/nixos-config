# =============================================================================
# etcd HA Cluster Module
# =============================================================================
#
# Purpose: Configure 3-node etcd cluster for Kubernetes control plane
#
# Architecture:
#   - Quorum-based cluster (2/3 nodes required for operation)
#   - TLS for all communication (peer, client, server)
#   - Leader election automatic
#   - Data replication across all nodes
#
# Nodes:
#   - Zephyr (10.1.1.110): etcd-0
#   - Nexus (10.1.1.120): etcd-1
#   - Sentry (10.1.1.140): etcd-2
#
# Usage:
#   Import this module on each master node and configure:
#   services.etcd-cluster = {
#     enable = true;
#     nodeName = "zephyr";  # or "nexus" or "sentry"
#   };
#
# =============================================================================
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.etcd-cluster;

  # etcd cluster configuration
  clusterNodes = {
    zephyr = {
      name = "etcd-0";
      ip = "10.1.1.110";
      peerUrl = "https://10.1.1.110:2380";
      clientUrl = "https://10.1.1.110:2379";
    };
    nexus = {
      name = "etcd-1";
      ip = "10.1.1.120";
      peerUrl = "https://10.1.1.120:2380";
      clientUrl = "https://10.1.1.120:2379";
    };
    sentry = {
      name = "etcd-2";
      ip = "10.1.1.140";
      peerUrl = "https://10.1.1.140:2380";
      clientUrl = "https://10.1.1.140:2379";
    };
  };

  # Current node configuration
  thisNode = clusterNodes.${cfg.nodeName} or null;

  # Cluster state string for initial cluster
  initialCluster = concatStringsSep "," (
    mapAttrsToList (_name: node: "${node.name}=https://${node.ip}:2380") clusterNodes
  );
in {
  options.services.etcd-cluster = {
    enable = mkEnableOption "etcd HA cluster for Kubernetes";

    nodeName = mkOption {
      type = types.enum ["zephyr" "nexus" "sentry"];
      description = "Name of this node in the etcd cluster";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/etcd";
      description = "Data directory for etcd";
    };

    pkiPath = mkOption {
      type = types.path;
      default = "/etc/kubernetes/pki";
      description = "Path to PKI certificates";
    };
  };

  config = mkIf (cfg.enable && thisNode != null) {
    # ========================================================================
    # ETCD SERVICE CONFIGURATION
    # ========================================================================
    services.etcd = {
      enable = true;

      # Server configuration
      inherit (thisNode) name;
      inherit (cfg) dataDir;

      # Listen addresses
      listenPeerUrls = ["https://${thisNode.ip}:2380"];
      listenClientUrls = ["https://${thisNode.ip}:2379" "https://127.0.0.1:2379"];

      # Advertise addresses
      advertiseClientUrls = ["https://${thisNode.ip}:2379"];
      initialAdvertisePeerUrls = ["https://${thisNode.ip}:2380"];

      # Cluster configuration
      inherit initialCluster;
      initialClusterToken = "kubernetes-etcd-cluster";
      initialClusterState = "new";

      # Security - TLS certificates
      # Note: These are set by kubernetes-ha.nix module
      # peerCertFile = "${cfg.pkiPath}/etcd-peer.pem";
      # peerKeyFile = config.age.secrets."etcd-peer-key".path;
      # peerTrustedCaFile = "${cfg.pkiPath}/ca.pem";
      # certFile = "${cfg.pkiPath}/etcd-${cfg.nodeName}.pem";
      # keyFile = config.age.secrets."etcd-${cfg.nodeName}-key".path;
      # trustedCaFile = "${cfg.pkiPath}/ca.pem";

      # Client authentication (API server)
      clientCertAuth = true;

      # Performance tuning
      snapshotCount = 10000;
      heartbeatInterval = 100;
      electionTimeout = 1000;
      quotaBackendBytes = 2147483648; # 2GB

      # Logging
      logLevel = "info";
      debug = false;
    };

    # ========================================================================
    # FIREWALL - etcd ports
    # ========================================================================
    networking.firewall = {
      allowedTCPPorts = [
        2379 # etcd client port
        2380 # etcd peer port
      ];
    };

    # ========================================================================
    # SYSTEMD SERVICE OVERRIDES
    # ========================================================================
    systemd.services.etcd = {
      # Ensure etcd starts before Kubernetes API server
      before = ["kube-apiserver.service"];

      # Restart on failure
      serviceConfig.Restart = "on-failure";
      serviceConfig.RestartSec = "5s";

      # Health check
      postStart = ''
        # Wait for etcd to be healthy
        for i in {1..30}; do
          if ETCDCTL_API=3 etcdctl \
            --endpoints=https://${thisNode.ip}:2379 \
            --cacert=${cfg.pkiPath}/ca.pem \
            --cert=${cfg.pkiPath}/etcd-${cfg.nodeName}.pem \
            --key=${config.age.secrets."etcd-${cfg.nodeName}-key".path} \
            endpoint health; then
            echo "etcd is healthy"
            exit 0
          fi
          echo "Waiting for etcd to be healthy... ($i/30)"
          sleep 1
        done
        echo "etcd health check failed"
        exit 1
      '';
    };

    # ========================================================================
    # MONITORING - etcd metrics endpoint
    # ========================================================================
    services.prometheus.exporters.etcd = mkIf config.services.prometheus.enable {
      enable = true;
      etcdHost = thisNode.ip;
      etcdPort = 2379;
      caCert = "${cfg.pkiPath}/ca.pem";
      clientCert = "${cfg.pkiPath}/etcd-${cfg.nodeName}.pem";
      clientKey = config.age.secrets."etcd-${cfg.nodeName}-key".path;
    };
  };
}
