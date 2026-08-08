{ config, lib, pkgs, ... }:

# memlawb encrypted-memory server (zero-knowledge, fs blobstore).
#
# Runs the memlawb Bun app as a systemd service. The Hermes MCP client
# (mcp_servers.memlawb in ~/.hermes/config.yaml) points MEMLAWB_URL at this
# host so cross-session memory survives even when nexus (the former backend)
# is offline.
#
# INTERIM SOURCE: the app is cloned to /persistent/memlawb (a git checkout,
# not a Nix store path) because memlawb is not yet packaged in nixpkgs and
# the nexus builder was unavailable to produce a closure. When memlawb is
# packaged (or added as a flake input), replace ExecStart with the store path.
# Data persists under /persistent/memlawb-data (survives generation rollback
# because /persistent is the impermanence/preservation root on this host).
#
# Enable per-host, e.g. in hosts/<host>/configuration.nix:
#   services.memlawb-server.enable = true;
{
  options.services.memlawb-server = {
    enable = lib.mkEnableOption "memlawb encrypted memory server";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "TCP port for the memlawb HTTP API";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/persistent/memlawb-data";
      description = "Directory for the fs blobstore (must outlive rebuilds)";
    };
    appDir = lib.mkOption {
      type = lib.types.str;
      default = "/persistent/memlawb";
      description = "Path to the memlawb checkout (src/index.ts entrypoint)";
    };
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Bind address for the memlawb HTTP API";
    };
  };

  config = lib.mkIf config.services.memlawb-server.enable {
    systemd.tmpfiles.rules = [
      "d \${config.services.memlawb-server.dataDir} 0755 j_kro users -"
    ];

    systemd.services.memlawb-server = {
      description = "memlawb encrypted memory server (fs store)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        User = "j_kro";
        Group = "users";
        Restart = "on-failure";
        RestartSec = "5s";
        Environment = [
          "STORE=fs"
          "DATA_DIR=\${config.services.memlawb-server.dataDir}"
          "PORT=\${toString config.services.memlawb-server.port}"
          "ALLOW_UNAUTHENTICATED=true"
        ];
        ExecStart = "\${pkgs.bun}/bin/bun run \${config.services.memlawb-server.appDir}/src/index.ts";
        WorkingDirectory = config.services.memlawb-server.appDir;
      };
    };

    networking.firewall.extraInputRules = lib.mkAfter ''
      ip saddr 10.1.1.0/24 tcp dport ${toString config.services.memlawb-server.port} accept
      iifname "lo" tcp dport ${toString config.services.memlawb-server.port} accept
    '';
  };
}
