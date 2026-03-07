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
    generators
    ;

  # GlitchTip Docker image
  glitchtipImage = "glitchtip/glitchtip:latest";
  postgresImage = "postgres:16-alpine";
  redisImage = "redis:7-alpine";

  # Data directories
  stateDir = "/var/lib/glitchtip";

  # Quadlet directory
  quadletDir = "/etc/containers/systemd";
in {
  options.services.glitchtip-selfhosted = {
    enable = mkEnableOption "GlitchTip error tracking service";

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address to bind to";
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
      "d ${stateDir}/postgres 0700 root root - -"
      "d ${stateDir}/redis 0700 root root - -"
      "d ${stateDir}/glitchtip 0700 root root - -"
      "d ${quadletDir} 0755 root root - -"
    ];

    # ============================================================================
    # QUADLET FILES (Podman native systemd integration)
    # ============================================================================

    # Pod definition
    environment.etc."containers/systemd/glitchtip.pod".text = generators.toINI {} {
      Pod = {
        Name = "glitchtip";
        PublishPort = "${cfg.host}:${toString cfg.port}:8000";
      };
    };

    # PostgreSQL container
    environment.etc."containers/systemd/glitchtip-postgres.container".text = generators.toINI {} {
      Container = {
        Image = postgresImage;
        PodName = "glitchtip";
        ContainerName = "glitchtip-postgres";
        Volume = "${stateDir}/postgres:/var/lib/postgresql/data:Z,${cfg.database.passwordFile}:/run/secrets/db-password:ro,Z";
        Environment = "POSTGRES_DB=${cfg.database.name}\nPOSTGRES_USER=${cfg.database.user}\nPOSTGRES_PASSWORD_FILE=/run/secrets/db-password";
      };
    };

    # Redis container
    environment.etc."containers/systemd/glitchtip-redis.container".text = generators.toINI {} {
      Container = {
        Image = redisImage;
        PodName = "glitchtip";
        ContainerName = "glitchtip-redis";
        Volume = "${stateDir}/redis:/data:Z";
      };
    };

    # GlitchTip web container
    environment.etc."containers/systemd/glitchtip-web.container".text = generators.toINI {} {
      Container = {
        Image = glitchtipImage;
        PodName = "glitchtip";
        ContainerName = "glitchtip-web";
        Volume = "${cfg.database.passwordFile}:/run/secrets/db-password:ro,Z,${cfg.secretKeyFile}:/run/secrets/secret-key:ro,Z";
        Environment = ''
          DATABASE_URL=postgres://${cfg.database.user}:$(cat ${cfg.database.passwordFile})@glitchtip-postgres:${toString cfg.database.port}/${cfg.database.name}
          REDIS_URL=redis://glitchtip-redis:${toString cfg.redis.port}/0
          SECRET_KEY=$(cat ${cfg.secretKeyFile})
          PORT=8000
          DEFAULT_FROM_EMAIL=glitchtip@localhost
          ACCOUNT_SIGNUP_ENABLED=true
          GLITCHTIP_DOMAIN=http://${cfg.host}:${toString cfg.port}
        '';
        Exec = "/usr/bin/env bash -c 'export DATABASE_URL=\"postgres://${cfg.database.user}:$(cat /run/secrets/db-password)@glitchtip-postgres:${toString cfg.database.port}/${cfg.database.name}\" && export REDIS_URL=\"redis://glitchtip-redis:${toString cfg.redis.port}/0\" && export SECRET_KEY=\"$(cat /run/secrets/secret-key)\" && export PORT=8000 && export DEFAULT_FROM_EMAIL=\"glitchtip@localhost\" && export ACCOUNT_SIGNUP_ENABLED=true && export GLITCHTIP_DOMAIN=\"http://${cfg.host}:${toString cfg.port}\" && exec /app/bin/start.sh'";
      };
    };

    # ============================================================================
    # SYSTEMD SERVICE RELOAD
    # ============================================================================
    systemd.services."pod-glitchtip" = {
      unitConfig.Requires = ["glitchtip-postgres.container" "glitchtip-redis.container" "glitchtip-web.container"];
    };

    # ============================================================================
    # FIREWALL
    # ============================================================================
    networking.firewall.allowedTCPPorts =
      optional cfg.openFirewall cfg.port;

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
