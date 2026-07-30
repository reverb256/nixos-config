{
  config,
  lib,
  pkgs,
  ...
}:

with lib; let
  cfg = config.services.gitlawb-node;

  # Shared user/group from programs.gitlawb (if enabled) or standalone defaults
  user = config.programs.gitlawb.user or "gitlawb";
  group = config.programs.gitlawb.group or "gitlawb";
  dataDir = config.programs.gitlawb.dataDir or cfg.dataDir;

  pgPassFile = "${dataDir}/pg-pass.env";
  hostIp = config.clusterNetworking.ipAddress or "127.0.0.1";
in {
  options.services.gitlawb-node = {
    enable = mkEnableOption "Gitlawb node — self-hosted decentralized git (private mirror)";

    httpPort = mkOption {
      type = types.port;
      default = 7545;
      description = "HTTP API + git smart-HTTP port (bound to hostIp, LAN-scoped).";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/gitlawb";
      description = ''
        Persistent storage for node data + generated identity key.
        Shared with `programs.gitlawb.dataDir` when both are enabled.
      '';
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/gitlawb/node:0.7.0";
      description = ''
        Gitlawb node container image. Pinned to a versioned tag;
        `:latest` is blocked by cluster admission policy.
      '';
    };

    postgresImage = mkOption {
      type = types.str;
      default = "docker.io/library/postgres:16-alpine";
      description = "Postgres container image for the node's private metadata store.";
    };

    postgresPassword = mkOption {
      type = types.str;
      default = "gitlawb-dev";
      description = ''
        Postgres password for the gitlawb role. Written to a root-owned 0600
        file (`<literal>pgPassFile</literal>`); upgrade to secretspec before production use.
      '';
    };

    extraEnv = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = ''
        Additional environment variables to pass to the gitlawb-node container.
        Merged with the defaults — override any built-in var here.
      '';
    };
  };

  config = mkIf cfg.enable {
    virtualisation.podman.enable = true;

    # -----------------------------------------------------------------------
    # Private podman network for gitlawb (node <-> postgres)
    # -----------------------------------------------------------------------
    systemd.services.gitlawb-net-create = {
      description = "Create gitlawb podman network";
      after = ["podman.service"];
      wantedBy = ["multi-user.target"];
      path = [pkgs.podman];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.podman}/bin/podman network create gitlawb-net";
        ExecStartPost = "${pkgs.podman}/bin/podman network exists gitlawb-net";
      };
    };

    # -----------------------------------------------------------------------
    # Data directory with tmpfiles (StateDirectory-style)
    # -----------------------------------------------------------------------
    systemd.tmpfiles.settings."gitlawb-node" = {
      "${dataDir}".d = {
        mode = "700";
        user = user;
        group = group;
      };
      "${pgPassFile}".f = {
        mode = "600";
        user = "root";
        group = "root";
      };
    };

    # -----------------------------------------------------------------------
    # Postgres (private podman container, gitlawb-net only)
    # -----------------------------------------------------------------------
    systemd.services.gitlawb-postgres = {
      description = "Gitlawb private Postgres";
      after = ["podman.service" "gitlawb-net-create.service"];
      requires = ["gitlawb-net-create.service"];
      wantedBy = ["multi-user.target"];
      path = [pkgs.podman];
      preStart = ''
        install -d -m700 ${dataDir}/pg
      '';
      serviceConfig = {
        Type = "simple";
        ExecStart = ''
          ${pkgs.podman}/bin/podman run \
            --name gitlawb-pg \
            --replace \
            --network gitlawb-net \
            --rm \
            -v ${dataDir}/pg:/var/lib/postgresql/data:Z \
            -e POSTGRES_DB=gitlawb \
            -e POSTGRES_USER=gitlawb \
            -e POSTGRES_PASSWORD=${cfg.postgresPassword} \
            ${cfg.postgresImage}
        '';
        ExecStop = "${pkgs.podman}/bin/podman stop --ignore gitlawb-pg";
        Restart = "on-failure";
        RestartSec = "5s";
        # Hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [dataDir "/var/lib/containers/storage" "/run/podman" "/var/lib/containers"];
        NoNewPrivileges = true;
        CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE" "CAP_CHOWN" "CAP_DAC_OVERRIDE" "CAP_FOWNER" "CAP_SETGID" "CAP_SETUID"];
      };
    };

    # -----------------------------------------------------------------------
    # Gitlawb node (private, isolated mirror)
    # -----------------------------------------------------------------------
    systemd.services.gitlawb-node = {
      description = "Gitlawb node — decentralized git (private mirror)";
      after = ["network-online.target" "podman.service" "gitlawb-postgres.service"];
      requires = ["gitlawb-postgres.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      path = [pkgs.podman];

      preStart = ''
        install -d -m700 ${dataDir}
        install -m600 <(printf 'POSTGRES_PASSWORD=%s\n' ${escapeShellArg cfg.postgresPassword}) ${pgPassFile}
      '';

      serviceConfig = {
        Type = "simple";
        ExecStart = let
          baseEnv = {
            DATABASE_URL = "postgresql://gitlawb:${cfg.postgresPassword}@gitlawb-pg:5432/gitlawb";
            GITLAWB_HOST = "0.0.0.0";
            GITLAWB_PORT = toString cfg.httpPort;
            GITLAWB_PUBLIC_URL = "http://${hostIp}:${toString cfg.httpPort}";
            GITLAWB_P2P_PORT = "0";
            GITLAWB_BOOTSTRAP_DISABLE_SEEDS = "true";
            GITLAWB_REQUIRE_SIGNED_PEER_WRITES = "false";
            GITLAWB_PUBLIC_READ = "false";
            GITLAWB_AUTO_SYNC = "false";
            GITLAWB_MAX_PACK_BYTES = "2147483648";
          };
          mergedEnv = baseEnv // cfg.extraEnv;
          envFlags = lib.concatStringsSep " \\\n            " (
            lib.mapAttrsToList (k: v: "-e ${k}=${escapeShellArg v}") mergedEnv
          );
        in ''
          ${pkgs.podman}/bin/podman run \
            --name gitlawb-node \
            --replace \
            --network gitlawb-net \
            --rm \
            -p ${hostIp}:${toString cfg.httpPort}:${toString cfg.httpPort} \
            -v ${dataDir}:/data:Z \
            --env-file ${pgPassFile} \
            ${envFlags} \
            ${cfg.image}
        '';
        ExecStop = "${pkgs.podman}/bin/podman stop --ignore gitlawb-node";
        Restart = "on-failure";
        RestartSec = "5s";
        # Hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [dataDir "/var/lib/containers/storage" "/run/podman" "/var/lib/containers"];
        NoNewPrivileges = true;
      };
    };

    # -----------------------------------------------------------------------
    # Firewall: open httpPort bound to hostIp (LAN-scoped only)
    # -----------------------------------------------------------------------
    networking.firewall.allowedTCPPorts = mkOptionDefault [cfg.httpPort];
  };
}
