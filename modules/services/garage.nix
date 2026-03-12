# Garage S3-compatible object storage
# Distributed object storage for cluster
{config, lib, pkgs, ...}: let
  cfg = config.services.garage-cluster;
in {
  options.services.garage-cluster = {
    enable = lib.mkEnableOption "Garage S3-compatible object storage";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/garage";
      description = "Directory for Garage data";
    };

    rpcPort = lib.mkOption {
      type = lib.types.port;
      default = 3901;
      description = "RPC port for cluster communication";
    };

    s3ApiPort = lib.mkOption {
      type = lib.types.port;
      default = 3900;
      description = "S3 API port";
    };

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 3902;
      description = "Web interface port";
    };

    peers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of peer nodes for clustering";
    };

    replicationFactor = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Replication factor for stored objects";
    };
  };

  config = lib.mkIf cfg.enable {
    # Garage package and service
    environment.systemPackages = [pkgs.garage];

    systemd.services.garage = {
      description = "Garage S3-compatible object storage";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = "garage";
        Group = "garage";
        DynamicUser = true;

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
       ReadWritePaths = "${cfg.dataDir}";

        # Create data directory structure
        ExecStartPre = pkgs.writeShellScript "garage-init" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          # Create data directory and subdirectories
          mkdir -p "${cfg.dataDir}/meta"
          mkdir -p "${cfg.dataDir}/data"

          # Generate config if not exists
          if [[ ! -f "${cfg.dataDir}/garage.toml" ]]; then
            cat > "${cfg.dataDir}/garage.toml" <<'EOF'
metadata_dir = "${cfg.dataDir}/meta"
data_dir = "${cfg.dataDir}/data"

db_engine = "lmdb"

# RPC configuration
block_resync_tries = 10
block_resync_interval = "1h"

# S3 API
s3_api.api_bind_addr = "127.0.0.1:${toString cfg.s3ApiPort}"
s3_api.s3_region = "garage"
s3_api.root_domain = ".s3.garage.cluster"

# RPC
rpc_bind_addr = "0.0.0.0:${toString cfg.rpcPort}"
rpc_public_addr = "$(hostname -i | head -1):${toString cfg.rpcPort}"
rpc_secret = "$(openssl rand -hex 32)"

# Web interface
admin.api_bind_addr = "127.0.0.1:${toString cfg.webPort}"
admin.metrics_token = "$(openssl rand -hex 32)"

# Replication
replication_factor = ${toString cfg.replicationFactor}

# Consul discovery (disabled for static config)
# consul_discovery.consul_http_addr = "http://127.0.0.1:8500"
# consul_discovery.consul_service_name = "garage"

# Kubernetes discovery (disabled)
# kubernetes_discovery.kubernetes_namespace = "default"
# kubernetes_discovery.service_name = "garage"
# kubernetes_discovery.skip_crd = false
EOF
          fi
        '';

        ExecStart = "${pkgs.garage}/bin/garage -c ${cfg.dataDir}/garage.toml server";

        # Hardening
        CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
        AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictRealtime = true;
        SystemCallFilter = ["@system-service" "~@privileged"];
        MemoryDenyWriteExecute = true;
      };
    };

    # Firewall - use mkOptionDefault to preserve existing ports
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
      cfg.rpcPort    # RPC for cluster communication
      cfg.s3ApiPort  # S3 API
    ];
  };
}
