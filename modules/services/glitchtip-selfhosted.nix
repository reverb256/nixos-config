# GlitchTip Error Tracking Service
# Self-hosted Sentry alternative using Podman
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.glitchtip-selfhosted;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    optional
    literalExpression
    ;

  # GlitchTip Docker image
  glitchtipImage = "glitchtip/glitchtip:latest";
  postgresImage = "postgres:16-alpine";
  redisImage = "redis:7-alpine";

  # Data directories
  stateDir = "/var/lib/glitchtip";
in {
  options.services.glitchtip-selfhosted = {
    enable = mkEnableOption "GlitchTip error tracking service";

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";  # SECURITY: Bind to localhost only
      description = "Host address to bind to (127.0.0.1 for localhost-only)";
    };

    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Port for the GlitchTip web interface";
    };

    # Database configuration
    database = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "PostgreSQL host (container name if using podman)";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "PostgreSQL port";
      };

      name = mkOption {
        type = types.str;
        default = "glitchtip";
        description = "Database name";
      };

      user = mkOption {
        type = types.str;
        default = "glitchtip";
        description = "Database user";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = literalExpression "/run/agenix/glitchtip-db-password";
        description = "Path to file containing database password";
      };
    };

    # Redis configuration
    redis = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Redis host";
      };

      port = mkOption {
        type = types.port;
        default = 6379;
        description = "Redis port";
      };
    };

    # Secret key for Django
    secretKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = literalExpression "/run/agenix/glitchtip-secret-key";
      description = "Path to file containing Django secret key";
    };

    # Open firewall
    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall for the GlitchTip port";
    };

    # Enable for AI inference gateway integration
    enableForGateway = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically configure AI inference gateway to use GlitchTip";
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # PODMAN SETUP
    # ============================================================================
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    environment.systemPackages = with pkgs; [podman-compose];

    # ============================================================================
    # STATE DIRECTORY
    # ============================================================================
    systemd.tmpfiles.rules = [
      "d ${stateDir}/postgres 0700 999 999 - -"
      "d ${stateDir}/redis 0700 999 999 - -"
      "d ${stateDir}/glitchtip 0700 root root - -"
    ];

    # ============================================================================
    # WRAPPER SCRIPTS
    # ============================================================================
    # Script to start GlitchTip web container with secrets
    environment.etc."glitchtip/start-web.sh".text = ''
      #!${pkgs.bash}/bin/sh
      set -euo pipefail

      # Read secrets before passing to container (containers can't read /run/agenix directly)
      DB_PASS=$(${pkgs.coreutils}/bin/cat ${cfg.database.passwordFile})
      SECRET_KEY=$(${pkgs.coreutils}/bin/cat ${cfg.secretKeyFile})

      # Export for podman run
      export DATABASE_URL="postgres://${cfg.database.user}:$${DB_PASS}@glitchtip-postgres:${toString cfg.database.port}/${cfg.database.name}"
      export REDIS_URL="redis://glitchtip-redis:${toString cfg.redis.port}/0"
      export SECRET_KEY
      export PORT="8000"
      export DEFAULT_FROM_EMAIL="glitchtip@localhost"
      export ACCOUNT_SIGNUP_ENABLED="true"
      export GLITCHTIP_DOMAIN="http://${cfg.host}:${toString cfg.port}"

      # Start the container
      exec ${pkgs.podman}/bin/podman run --rm --replace --name glitchtip-web \
        --pod glitchtip \
        -e DATABASE_URL \
        -e REDIS_URL \
        -e SECRET_KEY \
        -e PORT \
        -e DEFAULT_FROM_EMAIL \
        -e ACCOUNT_SIGNUP_ENABLED \
        -e GLITCHTIP_DOMAIN \
        ${glitchtipImage}
    '';

    # ============================================================================
    # PODMAN POD (containers share network namespace)
    # ============================================================================
    systemd.services.glitchtip-pod = {
      description = "GlitchTip Pod (shared network namespace)";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.podman}/bin/podman pod create --name glitchtip --publish ${cfg.host}:${toString cfg.port}:8000";
        ExecStop = "${pkgs.podman}/bin/podman pod rm -f glitchtip";
        Restart = "on-failure";
      };
    };

    # ============================================================================
    # POSTGRESQL CONTAINER
    # ============================================================================
    systemd.services.glitchtip-postgres = {
      description = "GlitchTip PostgreSQL database";
      after = ["glitchtip-pod.service"];
      wantedBy = ["multi-user.target"];
      partOf = ["glitchtip-pod.service"];
      serviceConfig = {
        ExecStart = ''
          ${pkgs.bash}/bin/sh -c 'DB_PASS=$(${pkgs.coreutils}/bin/cat ${cfg.database.passwordFile}) && \
          ${pkgs.podman}/bin/podman run --rm --replace --name glitchtip-postgres \
            --pod glitchtip \
            -e POSTGRES_DB=${cfg.database.name} \
            -e POSTGRES_USER=${cfg.database.user} \
            -e POSTGRES_PASSWORD=$${DB_PASS} \
            -v ${stateDir}/postgres:/var/lib/postgresql/data:Z \
            ${postgresImage}'
        '';
        ExecStop = "${pkgs.podman}/bin/podman stop glitchtip-postgres";
        Restart = "always";
        RestartSec = "10s";
      };
    };

    # ============================================================================
    # REDIS CONTAINER
    # ============================================================================
    systemd.services.glitchtip-redis = {
      description = "GlitchTip Redis cache";
      after = ["glitchtip-pod.service"];
      wantedBy = ["multi-user.target"];
      partOf = ["glitchtip-pod.service"];
      serviceConfig = {
        ExecStart = "${pkgs.podman}/bin/podman run --rm --replace --name glitchtip-redis --pod glitchtip -v ${stateDir}/redis:/data:Z ${redisImage}";
        ExecStop = "${pkgs.podman}/bin/podman stop glitchtip-redis";
        Restart = "always";
        RestartSec = "10s";
      };
    };

    # ============================================================================
    # GLITCHTIP WEB CONTAINER
    # ============================================================================
    systemd.services.glitchtip-web = {
      description = "GlitchTip error tracking web interface";
      after = [
        "glitchtip-postgres.service"
        "glitchtip-redis.service"
      ];
      wantedBy = ["multi-user.target"];
      partOf = ["glitchtip-pod.service"];
      serviceConfig = {
        ExecStart = "${pkgs.bash}/bin/sh /etc/glitchtip/start-web.sh";
        ExecStop = "${pkgs.podman}/bin/podman stop glitchtip-web";
        Restart = "always";
        RestartSec = "10s";
      };
    };

    # ============================================================================
    # FIREWALL
    # ============================================================================
    networking.firewall.allowedTCPPorts =
      optional cfg.openFirewall cfg.port;

    # ============================================================================
    # SERVICE ACCESS PERMISSIONS
    # ============================================================================
    systemd.services.glitchtip-postgres.serviceConfig.ReadOnlyPaths =
      mkIf (cfg.database.passwordFile != null) [cfg.database.passwordFile];
    systemd.services.glitchtip-web.serviceConfig.ReadOnlyPaths =
      lib.optional (cfg.database.passwordFile != null) cfg.database.passwordFile
      ++ lib.optional (cfg.secretKeyFile != null) cfg.secretKeyFile;

    # ============================================================================
    # AI INFERENCE GATEWAY INTEGRATION
    # ============================================================================
    services.ai-inference.sentry = mkIf cfg.enableForGateway {
      enable = true;
      dsn = "http://glitchtip:${toString cfg.port}@${cfg.host}:${toString cfg.port}/1";
      environment = "production";
      tracesSampleRate = 0.1;
    };
  };
}
