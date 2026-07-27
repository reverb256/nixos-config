{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.gitlawb-node;

  # Isolated-by-default: we run a private mirror, NOT a federated node.
  # No libp2p gossip, no seed bootstrap, HTTP API bound to LAN only.
  pgPassFile = "/var/lib/gitlawb/pg-pass.env";
in {
  options.services.gitlawb-node = {
    enable = mkEnableOption "Gitlawb node — self-hosted decentralized git (private mirror)";

    httpPort = mkOption {
      type = types.int;
      default = 7545;
      description = "HTTP API + git smart-HTTP port (LAN only).";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/gitlawb";
      description = "Persistent storage for node data + generated identity key.";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/gitlawb/node:latest";
      description = "Container image (multi-arch, published by upstream release CI).";
    };

    postgresPassword = mkOption {
      type = types.str;
      default = "gitlawb-dev";
      description = ''
        Postgres password for the gitlawb role. For a non-critical mirror this
        is written to a root-owned 0600 file (${pgPassFile}); upgrade to
        secretspec-creds before any production use.
      '';
    };
  };

  config = mkIf cfg.enable {
    # -----------------------------------------------------------------------
    # Postgres (native, integrated, LAN-only socket + localhost)
    # -----------------------------------------------------------------------
    services.postgresql = {
      enable = true;
      ensureDatabases = ["gitlawb"];
      ensureUsers = [
        {
          name = "gitlawb";
          ensureDBOwnership = true;
        }
      ];
      settings = {
        listen_addresses = "127.0.0.1";
        port = 5432;
      };
      authentication = pkgs.lib.mkOverride 10 ''
        local   all all trust
        host    all all 127.0.0.1/32 trust
      '';
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
    # Podman service (mirrors upstream docker-compose node service)
    # -----------------------------------------------------------------------
    virtualisation.podman.enable = true;

    systemd.services.gitlawb-node = {
      description = "Gitlawb node — decentralized git (private mirror)";
      after = ["network-online.target" "podman.service" "postgresql.service"];
      requires = ["postgresql.service"];
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
            --network host \
            --rm \
            -v ${cfg.dataDir}:/data:Z \
            --env-file ${pgPassFile} \
            -e DATABASE_URL=postgresql://gitlawb:${cfg.postgresPassword}@127.0.0.1:5432/gitlawb \
            -e GITLAWB_HOST=0.0.0.0 \
            -e GITLAWB_PORT=${toString cfg.httpPort} \
            -e GITLAWB_PUBLIC_URL=http://10.1.1.140:${toString cfg.httpPort} \
            -e GITLAWB_P2P_PORT=0 \
            -e GITLAWB_BOOTSTRAP_DISABLE_SEEDS=true \
            -e GITLAWB_REQUIRE_SIGNED_PEER_WRITES=false \
            -e GITLAWB_PUBLIC_READ=true \
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
    # Firewall: LAN only (cluster private subnet)
    # -----------------------------------------------------------------------
    networking.firewall.allowedTCPPorts = [cfg.httpPort];
  };
}
