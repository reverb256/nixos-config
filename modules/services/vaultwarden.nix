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
    ;
in {
  options.services.vaultwarden-module = {
    enable = mkEnableOption "Vaultwarden - Self-hosted password manager with FIDO2";

    hostName = mkOption {
      type = types.str;
      example = "vaultwarden.ts.net";
      description = "The hostname for Vaultwarden (use Tailscale Magic DNS)";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/vaultwarden";
      description = "Vaultwarden data directory (SQLite database, attachments, keys)";
    };

    port = mkOption {
      type = types.int;
      default = 8222;
      description = "Host port for Vaultwarden";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.podman.enable = true;

    systemd.tmpfiles.settings."vaultwarden" = {
      "${cfg.dataDir}" = {
        d = {
          mode = "700";
          user = "root";
          group = "root";
        };
      };
    };

    systemd.services.vaultwarden = {
      description = "Vaultwarden Password Manager";
      after = [
        "network-online.target"
        "podman.service"
      ];
      wants = [
        "podman.service"
        "network-online.target"
      ];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        ExecStart = ''
          ${pkgs.podman}/bin/podman run --name vaultwarden \
            -p ${toString cfg.port}:80 \
            -v ${cfg.dataDir}:/data:Z \
            -v ${config.age.secrets.vaultwarden-admin-token.path}:/run/secrets/admin-token:ro,Z \
            -v ${config.age.secrets.vaultwarden-oidc-client-secret.path}:/run/secrets/oidc-client-secret:ro,Z \
            -e WEBSOCKET_ENABLED=true \
            -e WEBSOCKET_ADDRESS=0.0.0.0 \
            -e DOMAIN=https://${cfg.hostName} \
            -e ADMIN_TOKEN_FILE=/run/secrets/admin-token \
            -e LOG_LEVEL=info \
            -e OIDC_CLIENT_ID=45b131ddd1706688495a \
            -e OIDC_CLIENT_SECRET_FILE=/run/secrets/oidc-client-secret \
            -e OIDC_AUTH_URL=https://auth.lan/login/oauth/authorize \
            -e OIDC_TOKEN_URL=https://auth.lan/api/login/oauth/access_token \
            -e OIDC_USERINFO_URL=https://auth.lan/api/userinfo \
            -e OIDC_SCOPES="openid profile email" \
            -e OIDC_ADMIN_VALIDATE=true \
            --replace \
            docker.io/vaultwarden/server:1.35.4
        '';

        ExecStop = "${pkgs.podman}/bin/podman stop --ignore vaultwarden";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f vaultwarden || true";

        Restart = "always";
        RestartSec = "10s";

        MemoryMax = "512M";
        CPUQuota = "50%";

        PrivateTmp = true;
        ProtectHome = true;

        ReadWritePaths = [
          cfg.dataDir
          config.age.secrets.vaultwarden-admin-token.path
          "/var/lib/containers/storage"
          "/run/podman"
          "/var/lib/containers"
        ];

        ProtectSystem = lib.mkForce "full";
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [cfg.port];

    environment.systemPackages = with pkgs; [vaultwarden];
  };
}
