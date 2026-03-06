# Qdrant Vector Database Service for RAG
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.ai-inference.rag;
  inherit (lib) mkIf optional;

  # Qdrant configuration file
  qdrantConfig = pkgs.writeText "qdrant-config.yaml" ''
    service:
      host: ${cfg.qdrant.host}
      http_port: ${toString cfg.qdrant.port}
      grpc_port: ${toString cfg.qdrant.grpcPort}

    storage:
      storage_path: ${cfg.qdrant.storagePath}

    telemetry:
      disable: true
  '';
in {
  config = mkIf (cfg.enable && cfg.qdrant.enable) {
    # Qdrant service
    systemd.services.qdrant = {
      description = "Qdrant Vector Database";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        ExecStart = "${cfg.qdrant.package}/bin/qdrant --config-path ${qdrantConfig}";
        Restart = "on-failure";
        RestartSec = "10s";
        User = "qdrant";
        Group = "qdrant";
        WorkingDirectory = cfg.qdrant.storagePath;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [cfg.qdrant.storagePath "${cfg.qdrant.storagePath}/snapshots" "/tmp"];
        MemoryMax = cfg.qdrant.memoryLimit;
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "qdrant";
      };
    };

    # Qdrant user
    users.users.qdrant = {
      isSystemUser = true;
      group = "qdrant";
      description = "Qdrant Vector Database";
    };
    users.groups.qdrant = {};

    # Create storage directory
    systemd.tmpfiles.rules = [
      "d ${cfg.qdrant.storagePath} 0750 qdrant qdrant - -"
    ];

    # Open firewall for Qdrant (optional, local only by default)
    networking.firewall.allowedTCPPorts = optional (cfg.qdrant.host != "127.0.0.1") cfg.qdrant.port;
  };
}
