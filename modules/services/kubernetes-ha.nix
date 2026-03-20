# =============================================================================
# Kubernetes HA - External PKI Integration Module
# =============================================================================
#
# Purpose: Configure Kubernetes to use externally generated certificates
#          instead of easyCerts, enabling custom SANs (VIP, hostnames)
#
# Features:
#   - Disables easyCerts (which only supports node IPs in SANs)
#   - Uses cfssl-generated certificates with VIP (10.1.1.100) in SANs
#   - Configures all control plane components for HA operation
#   - Supports VIP-based API server access
#
# Usage:
#   1. Generate certificates with: cd /etc/nixos/modules/pki && ./gen-certs.sh
#   2. Encrypt private keys with agenix
#   3. Import this module in host configuration
#   4. Set services.kubernetes.ha.enable = true
#
# =============================================================================
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.kubernetes.ha;
in {
  options.services.kubernetes.ha = {
    enable = mkEnableOption "Kubernetes HA with external PKI";

    vip = mkOption {
      type = types.str;
      default = "10.1.1.100";
      description = "Virtual IP for API server load balancer";
    };

    pkiPath = mkOption {
      type = types.path;
      default = "/etc/kubernetes/pki";
      description = "Path to PKI certificates";
    };

    etcdEndpoints = mkOption {
      type = types.listOf types.str;
      default = [
        "https://10.1.1.110:2379" # Zephyr
        "https://10.1.1.120:2379" # Nexus
        "https://10.1.1.140:2379" # Sentry
      ];
      description = "etcd cluster endpoints for API server";
    };

    masterNodes = mkOption {
      type = types.listOf types.str;
      default = ["10.1.1.110" "10.1.1.120" "10.1.1.140"];
      description = "IP addresses of master nodes for load balancer";
    };
  };

  config = mkIf cfg.enable {
    services = {
      kubernetes = {
        easyCerts = false;

        # ========================================================================
        # CA CERTIFICATE - Public, distributed to all nodes
        # ========================================================================
        caFile = "${cfg.pkiPath}/ca.pem";

        # ========================================================================
        # API SERVER CONFIGURATION
        # ========================================================================
        apiserver = {
          enable = true;

          # Bind to all interfaces for VIP support
          bindAddress = "0.0.0.0";

          # Secure port
          securePort = 6443;

          # Use external certificate with VIP in SANs
          serverCert = "${cfg.pkiPath}/apiserver.pem";
          serverKey = config.age.secrets."apiserver-key".path;

          # Client CA for authenticating client certificates
          clientCaFile = "${cfg.pkiPath}/ca.pem";

          # Kubelet client certificates
          kubeletClientCert = "${cfg.pkiPath}/apiserver.pem";
          kubeletClientKey = config.age.secrets."apiserver-key".path;

          # Service account key
          serviceAccountKeyFile = config.age.secrets."service-account-key".path or "${cfg.pkiPath}/service-account.pem";

          # Token auth file (if using static tokens)
          tokenAuthFile = config.age.secrets."token-auth".path or "${cfg.pkiPath}/tokens.csv";

          # OIDC (optional, configure for your IdP)
          # oidcIssuer = "https://your-oidc-provider";
          # oidcClientID = "kubernetes";
          # oidcUsernameClaim = "email";

          # etcd configuration for HA cluster
          etcd = {
            servers = cfg.etcdEndpoints;
            caFile = "${cfg.pkiPath}/ca.pem";
            certFile = "${cfg.pkiPath}/apiserver.pem";
            keyFile = config.age.secrets."apiserver-key".path;
          };

          # Authorization and admission
          authorizationMode = ["Node" "RBAC"];
          admissionControl = [
            "NodeRestriction"
            "NamespaceLifecycle"
            "ServiceAccount"
            "LimitRanger"
            "DefaultStorageClass"
            "DefaultTolerationSeconds"
            "ResourceQuota"
          ];

          # API server flags for HA
          extraOpts = [
            "--endpoint-reconciler-type=lease"
            "--enable-aggregator-routing=true"
            "--proxy-client-cert-file=${cfg.pkiPath}/front-proxy-client.pem"
            "--proxy-client-key-file=${config.age.secrets."front-proxy-client-key".path or "${cfg.pkiPath}/front-proxy-client-key.pem"}"
          ];

          # Service cluster IP range
          serviceClusterIpRange = "10.0.0.0/24";

          # Allow privileged containers
          allowPrivileged = true;
        };

        # ========================================================================
        # CONTROLLER MANAGER CONFIGURATION
        # ========================================================================
        controllerManager = {
          enable = true;

          # Client authentication
          rootCaFile = "${cfg.pkiPath}/ca.pem";
          kubeconfig = {
            server = "https://${cfg.vip}:6443";
            caFile = "${cfg.pkiPath}/ca.pem";
            certFile = "${cfg.pkiPath}/controller-manager.pem";
            keyFile = config.age.secrets."controller-manager-key".path;
          };

          # Cluster CIDR for pod networks
          clusterCidr = "10.244.0.0/16";

          # Service account private key
          serviceAccountPrivateKeyFile = config.age.secrets."service-account-key".path or "${cfg.pkiPath}/service-account-key.pem";

          # Leader election for HA
          extraOpts = [
            "--leader-elect=true"
            "--leader-elect-lease-duration=15s"
            "--leader-elect-renew-deadline=10s"
            "--leader-elect-retry-period=2s"
            "--use-service-account-credentials=true"
            "--cluster-name=homelab"
            "--v=2"
          ];
        };

        # ========================================================================
        # SCHEDULER CONFIGURATION
        # ========================================================================
        scheduler = {
          enable = true;

          # Client authentication
          kubeconfig = {
            server = "https://${cfg.vip}:6443";
            caFile = "${cfg.pkiPath}/ca.pem";
            certFile = "${cfg.pkiPath}/scheduler.pem";
            keyFile = config.age.secrets."scheduler-key".path;
          };

          # Leader election for HA
          extraOpts = [
            "--leader-elect=true"
            "--leader-elect-lease-duration=15s"
            "--leader-elect-renew-deadline=10s"
            "--leader-elect-retry-period=2s"
            "--kubeconfig=/etc/kubernetes/scheduler.kubeconfig"
            "--v=2"
          ];
        };

        # ========================================================================
        # KUBELET CONFIGURATION
        # ========================================================================
        kubelet.extraOpts = [
          "--cluster-dns=${config.services.kubernetes.dnsIp}"
          "--cluster-domain=cluster.local"
          "--container-runtime=remote"
          "--container-runtime-endpoint=unix:///run/podman/podman.sock"
          "--cgroup-driver=systemd"
          "--kubeconfig=/etc/kubernetes/kubelet.kubeconfig"
          "--network-plugin=cni"
          "--v=2"
        ];
      };

      # ========================================================================
      # ETCD PEER CERTIFICATES (for etcd-cluster module)
      # ========================================================================
      etcd = {
        # Peer certificates for etcd cluster communication
        peerCertFile = "${cfg.pkiPath}/etcd-peer.pem";
        peerKeyFile = config.age.secrets."etcd-peer-key".path;
        peerTrustedCaFile = "${cfg.pkiPath}/ca.pem";

        # Client certificates for API server communication
        certFile = "${cfg.pkiPath}/etcd-${config.networking.hostName}.pem";
        keyFile = config.age.secrets."etcd-${config.networking.hostName}-key".path;
        trustedCaFile = "${cfg.pkiPath}/ca.pem";
      };

      # ========================================================================
      # FIREWALL - Kubernetes API and etcd ports
      # ========================================================================
    };
    networking.firewall = {
      allowedTCPPorts = [
        6443 # Kubernetes API server
        2379 # etcd client
        2380 # etcd peer
      ];
    };

    # ========================================================================
    # AGE SECRETS - Private keys
    # ========================================================================
    age.secrets = let
      secretPath = path: "/etc/kubernetes/pki/${path}";
    in {
      "apiserver-key" = {
        file = ./../../secrets/apiserver-key.age;
        mode = "600";
        owner = "root";
        group = "root";
        path = secretPath "apiserver-key.pem";
      };

      "controller-manager-key" = {
        file = ./../../secrets/controller-manager-key.age;
        mode = "600";
        owner = "root";
        group = "root";
        path = secretPath "controller-manager-key.pem";
      };

      "scheduler-key" = {
        file = ./../../secrets/scheduler-key.age;
        mode = "600";
        owner = "root";
        group = "root";
        path = secretPath "scheduler-key.pem";
      };

      "etcd-peer-key" = {
        file = ./../../secrets/etcd-peer-key.age;
        mode = "600";
        owner = "root";
        group = "root";
        path = secretPath "etcd-peer-key.pem";
      };

      "etcd-zephyr-key" = mkIf (config.networking.hostName == "zephyr") {
        file = ./../../secrets/etcd-zephyr-key.age;
        mode = "600";
        owner = "root";
        group = "root";
        path = secretPath "etcd-zephyr-key.pem";
      };

      "etcd-nexus-key" = mkIf (config.networking.hostName == "nexus") {
        file = ./../../secrets/etcd-nexus-key.age;
        mode = "600";
        owner = "root";
        group = "root";
        path = secretPath "etcd-nexus-key.pem";
      };

      "etcd-sentry-key" = mkIf (config.networking.hostName == "sentry") {
        file = ./../../secrets/etcd-sentry-key.age;
        mode = "600";
        owner = "root";
        group = "root";
        path = secretPath "etcd-sentry-key.pem";
      };
    };

    # ========================================================================
    # SYSTEMD TMPFILES - Ensure PKI directory exists
    # ========================================================================
    systemd.tmpfiles.rules = [
      "d /etc/kubernetes/pki 0755 root root - -"
      "d /etc/kubernetes/manifests 0755 root root - -"
      "d /var/lib/kubernetes 0755 root root - -"
    ];
  };
}
