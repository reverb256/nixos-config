# Vaultwarden - Self-hosted Bitwarden-compatible password manager
# FIDO2/WebAuthn support + TOTP 2FA + YubiKey
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.vaultwarden-module;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkMerge
    mkDefault
    ;
in {
  options.services.vaultwarden-module = {
    enable = mkEnableOption "Vaultwarden - Self-hosted password manager with FIDO2";

    # ============================================================================
    # BASIC CONFIGURATION
    # ============================================================================
    hostName = mkOption {
      type = types.str;
      example = "vaultwarden.ts.net";
      description = "The hostname for Vaultwarden (use Tailscale Magic DNS)";
    };

    # ============================================================================
    # STORAGE
    # ============================================================================
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/containers/vaultwarden/data";
      description = "Vaultwarden data directory (SQLite database, attachments, keys)";
    };

    # ============================================================================
    # NETWORK
    # ============================================================================
    port = mkOption {
      type = types.int;
      default = 8080;
      description = "Host port for Vaultwarden (container always listens on 80)";
    };

    # ============================================================================
    # ADMIN ACCESS
    # ============================================================================
    adminTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/agenix/vaultwarden-admin-token";
      description = "Path to file containing admin token (use Agenix)";
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # PODMAN PACKAGE
    # ============================================================================
    virtualisation.podman.enable = true;

    # ============================================================================
    # DATA DIRECTORY SETUP
    # ============================================================================
    systemd.tmpfiles.settings."vaultwarden" = {
      "${cfg.dataDir}" = {
        d = {
          mode = "700";
          user = "root";
          group = "root";
        };
      };
    };

    # ============================================================================
    # PODMAN QUADLET CONFIGURATION
    # ============================================================================
    environment.etc."containers/systemd/vaultwarden.container".text = ''
      [Unit]
      Description=Vaultwarden Password Manager
      After=network-online.target caddy.service
      Wants=caddy.service

      [Container]
      Image=docker.io/vaultwarden/server:latest
      ContainerName=vaultwarden
      PublishPort=${toString cfg.port}:80
      Volume=${cfg.dataDir}:/data:Z
      Environment=WEBSOCKET_ENABLED=true
      Environment=WEBSOCKET_ADDRESS=0.0.0.0
      Environment=LOG_LEVEL=info
      ${lib.optionalString (cfg.adminTokenFile != null) "SetCredential=admin-token:%d/ADMIN_TOKEN_FILE"}
      AutoUpdate=registry
      Label=io.containers.autoupdate=registry

      [Service]
      Restart=always
      RestartSec=10
      MemoryMax=512M
      CPUQuota=50%
      NoNewPrivileges=true
      PrivateTmp=true
      ProtectSystem=strict
      ProtectHome=true
      ReadOnlyPaths=/usr
      ReadWritePaths=${cfg.dataDir}

      [Install]
      WantedBy=multi-user.target default.target
    '';

    # ============================================================================
    # SYSTEMD CREDENTIALS FOR ADMIN TOKEN
    # ============================================================================
    systemd.services.vaultwarden = mkIf (cfg.adminTokenFile != null) {
      serviceConfig.LoadCredential = [
        "ADMIN_TOKEN_FILE:${cfg.adminTokenFile}"
      ];
      environment = {
        ADMIN_TOKEN = "\${CREDENTIALS_DIRECTORY}/ADMIN_TOKEN_FILE";
      };
    };

    # ============================================================================
    # CADDY REVERSE PROXY INTEGRATION
    # ============================================================================
    services.caddy-module.${cfg.hostName} = {
      reverseProxy = "localhost:${toString cfg.port}";
      reverseProxyPort = 80;
    };

    # ============================================================================
    # FIREWALL (Tailscale interface only - no public exposure)
    # ============================================================================
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [cfg.port];

    # ============================================================================
    # PACKAGES
    # ============================================================================
    environment.systemPackages = with pkgs; [vaultwarden];
  };
}
