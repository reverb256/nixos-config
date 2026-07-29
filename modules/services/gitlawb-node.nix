{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.gitlawb-node;

  # Isolated-by-default: private mirror, NOT a federated node.
  # Self-contained: its own podman Postgres + node container on a private
  # podman network, so it never collides with the host's native Postgres
  # (owned by Nextcloud on sentry). No libp2p gossip, no seed bootstrap,
  # reads require signed requests.
  pgPassFile = "/var/lib/gitlawb/pg-pass.env";
  hostIp = config.clusterNetworking.ipAddress or "127.0.0.1";
in {
  options.services.gitlawb-node = {
    enable = mkEnableOption "Gitlawb node — self-hosted decentralized git (private mirror)";

    httpPort = mkOption {
      type = types.int;
      default = 7545;
      description = "HTTP API + git smart-HTTP port (bound to hostIp, LAN-scoped).";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/gitlawb";
      description = "Persistent storage for node data + generated identity key.";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/gitlawb/node:latest";
      description = "Gitlawb node container image (multi-arch, upstream release CI).";
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
        file (${pgPassFile}); upgrade to secretspec-creds before production use.
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
    # Secrets file for the node container (root-owned, 0600)
    # -----------------------------------------------------------------------
    systemd.tmpfiles.settings."gitlawb-node" = {
      "${cfg.dataDir}".d = {
        mode = "700";
        user = "gitlawb";
        group = "gitlawb";
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
        install -d -m700 ${cfg.dataDir}/pg
      '';
      serviceConfig = {
        Type = "simple";
        ExecStart = ''
          ${pkgs.podman}/bin/podman run \
            --name gitlawb-pg \
            --replace \
            --network gitlawb-net \
            --rm \
            -v ${cfg.dataDir}/pg:/var/lib/postgresql/data \
            -e POSTGRES_DB=gitlawb \
            -e POSTGRES_USER=gitlawb \
            -e POSTGRES_PASSWORD=${cfg.postgresPassword} \
            ${cfg.postgresImage}
        '';
        ExecStop = "${pkgs.podman}/bin/podman stop --ignore gitlawb-pg";
        Restart = "always";
        RestartSec = "5s";
        PrivateTmp = true;
        ProtectSystem = "full";
        ReadWritePaths = [cfg.dataDir "/var/lib/containers/storage" "/run/podman" "/var/lib/containers"];
      };
    };

    # -----------------------------------------------------------------------
    # Gitlawb node (private, isolated mirror)
    # -----------------------------------------------------------------------
    systemd.services.gitlawb-node = {
      description = "Gitlawb node — decentralized git (private mirror)";
      after = ["network-online.target" "podman.service" "gitlawb-postgres.service"];
      requires = ["gitlawb-postgres.service"];
      wantedBy = ["multi-user.target"];
      path = [pkgs.podman];

      preStart = ''
        install -d -m700 ${cfg.dataDir}
        install -m600 <(printf 'POSTGRES_PASSWORD=%s\n' ${escapeShellArg cfg.postgresPassword}) ${pgPassFile}
      '';

      serviceConfig = {
        Type = "simple";
        ExecStart = ''
          ${pkgs.podman}/bin/podman run \
            --name gitlawb-node \
            --replace \
            --network gitlawb-net \
            --rm \
            -p ${hostIp}:${toString cfg.httpPort}:${toString cfg.httpPort} \
            -v ${cfg.dataDir}:/data:Z \
            --env-file ${pgPassFile} \
            -e DATABASE_URL=postgresql://gitlawb:${cfg.postgresPassword}@gitlawb-pg:5432/gitlawb \
            -e GITLAWB_HOST=0.0.0.0 \
            -e GITLAWB_PORT=${toString cfg.httpPort} \
            -e GITLAWB_PUBLIC_URL=http://${hostIp}:${toString cfg.httpPort} \
            -e GITLAWB_P2P_PORT=0 \
            -e GITLAWB_BOOTSTRAP_DISABLE_SEEDS=true \
            -e GITLAWB_REQUIRE_SIGNED_PEER_WRITES=false \
            -e GITLAWB_PUBLIC_READ=false \
            -e GITLAWB_AUTO_SYNC=false \
            -e GITLAWB_MAX_PACK_BYTES=2147483648 \
            ${cfg.image}
        '';
        ExecStop = "${pkgs.podman}/bin/podman stop --ignore gitlawb-node";
        Restart = "always";
        RestartSec = "5s";
        PrivateTmp = true;
        ProtectSystem = "full";
        ReadWritePaths = [cfg.dataDir "/var/lib/containers/storage" "/run/podman" "/var/lib/containers"];
      };
    };

    # -----------------------------------------------------------------------
    # Firewall: open cfg.httpPort only (app binds to hostIp; not wildcard-listened)
    # mkOptionDefault: appends, doesn't replace other modules' ports
    # -----------------------------------------------------------------------
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.httpPort];
  };
}
