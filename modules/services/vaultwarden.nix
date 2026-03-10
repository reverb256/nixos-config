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
      default = "/var/lib/vaultwarden";
      description = "Vaultwarden data directory (SQLite database, attachments, keys)";
    };

    # ============================================================================
    # NETWORK
    # ============================================================================
    port = mkOption {
      type = types.int;
      default = 8222;  # Changed from 8080 to avoid conflict with LM Studio
      description = "Host port for Vaultwarden";
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
    # SYSTEMD SERVICE FOR VAULTWARDEN
    # ============================================================================
    systemd.services.vaultwarden = {
      description = "Vaultwarden Password Manager";
      after = ["network-online.target" "podman.service"];
      wants = ["podman.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        # Podman container run command
        ExecStart = ''
          ${pkgs.podman}/bin/podman run --name vaultwarden \
            -p ${toString cfg.port}:80 \
            -v ${cfg.dataDir}:/data:Z \
            -e WEBSOCKET_ENABLED=true \
            -e WEBSOCKET_ADDRESS=0.0.0.0 \
            -e LOG_LEVEL=info \
            --replace \
            docker.io/vaultwarden/server:latest
        '';

        ExecStop = "${pkgs.podman}/bin/podman stop --ignore vaultwarden";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f vaultwarden || true";

        # Auto-restart
        Restart = "always";
        RestartSec = "10s";

        # Resource limits
        MemoryMax = "512M";
        CPUQuota = "50%";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ReadOnlyPaths = "/usr";

        # Read-write paths for data and Podman
        ReadWritePaths = [
          cfg.dataDir
          "/var/lib/containers/storage"
          "/run/podman"
          "/var/lib/containers"
        ];

        # Less strict system protection for Podman
        ProtectSystem = lib.mkForce "full";
      };
    };

    # ============================================================================
    # CADDY REVERSE PROXY INTEGRATION
    # ============================================================================
    services.caddy-module.${cfg.hostName} = {
      reverseProxy = "localhost:${toString cfg.port}";
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
