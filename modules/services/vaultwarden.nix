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
      after = ["network-online.target" "podman.service"];
      wants = ["podman.service" "network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        ExecStart = ''
          ${pkgs.podman}/bin/podman run --name vaultwarden \
            -p ${toString cfg.port}:80 \
            -v ${cfg.dataDir}:/data:Z \
            -e WEBSOCKET_ENABLED=true \
            -e WEBSOCKET_ADDRESS=0.0.0.0 \
            -e LOG_LEVEL=info \
            --replace \
            docker.io/vaultwarden/server:1.35.4
        '';

        ExecStop = "${pkgs.podman}/bin/podman stop --ignore vaultwarden";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f vaultwarden || true";

        Restart = "always";
        RestartSec = "10s";

        MemoryMax = "512M";
        CPUQuota = "50%";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ReadOnlyPaths = "/usr";

        ReadWritePaths = [
          cfg.dataDir
          "/var/lib/containers/storage"
          "/run/podman"
          "/var/lib/containers"
        ];

        ProtectSystem = lib.mkForce "full";
      };
    };

    services.caddy-module.${cfg.hostName} = {
      reverseProxy = "localhost:${toString cfg.port}";
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [cfg.port];

    environment.systemPackages = with pkgs; [vaultwarden];
  };
}
