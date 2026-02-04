{
  config,
  lib,
  pkgs,
  ...
}: {
  options.services.openclaw.declarative = {
    enable = lib.mkEnableOption "OpenClaw AI Agent Gateway (Declarative Container)";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/openclaw/openclaw:latest";
      description = "OpenClaw container image";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 18789;
      description = "OpenClaw gateway port";
    };

    apiPort = lib.mkOption {
      type = lib.types.int;
      default = 18790;
      description = "OpenClaw API port";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openclaw";
      description = "OpenClaw state directory";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openclaw/data";
      description = "OpenClaw data directory";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/openclaw";
      description = "OpenClaw config directory";
    };

    memory = lib.mkOption {
      type = lib.types.str;
      default = "2G";
      description = "Container memory limit";
    };

    cpuShares = lib.mkOption {
      type = lib.types.int;
      default = 512;
      description = "Container CPU shares";
    };

    gatewayMode = lib.mkOption {
      type = lib.types.str;
      default = "local";
      description = "OpenClaw gateway mode";
    };

    gatewayBind = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "IP to bind gateway to";
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/agenix/openclaw-env";
      description = "Path to environment file";
    };

    enableLegacyEnv = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable legacy environment variables";
    };
  };

  config = let
    cfg = config.services.openclaw.declarative;
  in lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.podman];

    users.users.lobster = {
      isSystemUser = true;
      uid = 982;
      group = "lobster";
    };

    users.groups.lobster = {
      gid = 979;
    };

    systemd.services.openclaw-declarative = {
      enable = true;
      description = "OpenClaw AI Agent Gateway (Declarative Container)";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "openclaw-container-start" ''
          #!/usr/bin/env bash
          set -euo pipefail

          # Check if OpenClaw user exists
          if ! id -u lobster 2>/dev/null; then
            echo "Creating OpenClaw user..."
            sudo useradd -r -u 982 -g 979 -s /bin/bash -c "openclaw user" lobster || exit 1
          fi

          # Wait for user to be fully created
          while ! id -u lobster 2>/dev/null; do
            echo "Waiting for OpenClaw user to be available..."
            sleep 1
          done

          echo "Starting OpenClaw container..."

          # Create container storage directory with proper permissions
          ${pkgs.coreutils}/bin/mkdir -p /var/lib/containers/storage 2>/dev/null || true
          ${pkgs.coreutils}/bin/chown 982:979 /var/lib/containers/storage 2>/dev/null || true

          # Stop any existing container
          ${pkgs.podman}/bin/podman stop openclaw-declarative 2>/dev/null || true

          # Create Podman network for isolation
          ${pkgs.podman}/bin/podman network create openclaw-network 2>/dev/null || true

          # Start OpenClaw container
          exec ${pkgs.podman}/bin/podman run \
            --name openclaw-declarative \
            --network openclaw-network \
            --restart unless-stopped \
            -p "127.0.0.1:${toString cfg.port}:${toString cfg.apiPort}" \
            -v "${cfg.stateDir}:/var/lib/openclaw" \
            -v "${cfg.dataDir}:/var/lib/openclaw/data" \
            -v "${cfg.configDir}:/etc/openclaw" \
            -e "OPENCLAW_MODE=${cfg.gatewayMode}" \
            -e "OPENCLAW_BIND=${cfg.gatewayBind}" \
            -e "OPENCLAW_PORT=${toString cfg.port}" \
            -e "OPENCLAW_API_PORT=${toString cfg.apiPort}" \
            -e "OPENCLAW_STATE_DIR=${cfg.stateDir}" \
            -e "OPENCLAW_DATA_DIR=${cfg.dataDir}" \
            -e "OPENCLAW_CONFIG_DIR=${cfg.configDir}" \
            -e "OPENCLAW_GATEWAY_TOKEN=$(cat ${cfg.environmentFile} 2>/dev/null | grep OPENCLAW_GATEWAY_TOKEN | cut -d'=' -f2 || echo 'MISSING_SECRET')" \
            -e "OPENCLAW_NIX_MODE=1" \
            ${if cfg.enableLegacyEnv then "-e MOLTBOT_NIX_MODE=1" else ""} \
            --memory=${cfg.memory} \
            --cpu-shares=${toString cfg.cpuShares} \
            --userns=keep-id \
            --cap-drop ALL \
            --security-opt "no-new-privileges=true" \
            --label "managed-by=nixos" \
            --label "component=openclaw-gateway" \
            --label "environment=production" \
            "${cfg.image}" \
            node openclaw.mjs gateway --port ${toString cfg.port} --allow-unconfigured
        '';

        ExecStop = pkgs.writeShellScript "openclaw-container-stop" ''
          #!/usr/bin/env bash
          set -euo pipefail
          ${pkgs.podman}/bin/podman stop openclaw-declarative 2>/dev/null || true
        '';

        User = "root";
        Group = "root";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectHostname = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        RestrictAddressFamilies = "AF_INET AF_INET6";
        SystemCallFilter = ["@system-service" "@resources"];

        ReadWritePaths = [
          cfg.stateDir
          cfg.dataDir
          cfg.configDir
          "/var/lib/containers/storage"
        ];
      };

      after = ["network-online.target" "podman.service"];
      requires = ["podman.service"];
      wantedBy = ["multi-user.target"];
    };
  };
}
