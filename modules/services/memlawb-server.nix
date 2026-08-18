{
  config,
  lib,
  pkgs,
  ...
}:
# memlawb encrypted-memory server (zero-knowledge, fs blobstore).
#
# Runs the memlawb Bun app as a systemd service. The Hermes MCP client
# (mcp_servers.memlawb in ~/.hermes/config.yaml) points MEMLAWB_URL at this
# host so cross-session memory survives even when nexus (the former backend)
# is offline.
#
# Source is the pinned memlawb flake input, packaged into the Nix store (pkgs.memlawb).
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
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Bind address for the memlawb HTTP API";
    };
  };

  config = lib.mkIf config.services.memlawb-server.enable {
    systemd.tmpfiles.rules = [
      "d ${config.services.memlawb-server.dataDir} 0755 j_kro users -"
    ];

    systemd.services.memlawb-server = {
      description = "memlawb encrypted memory server (fs store)";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "simple";
        User = "j_kro";
        Group = "users";
        Restart = "on-failure";
        RestartSec = "5s";
        Environment = [
          "STORE=fs"
          "DATA_DIR=${config.services.memlawb-server.dataDir}"
          "PORT=${toString config.services.memlawb-server.port}"
          "ALLOW_UNAUTHENTICATED=true"
        ];
        ExecStart = "${pkgs.memlawb}/bin/memlawb-server";
        WorkingDirectory = "${pkgs.memlawb}/share/memlawb";
      };
    };

    networking.firewall.extraInputRules = lib.mkAfter ''
      ip saddr 10.1.1.0/24 tcp dport ${toString config.services.memlawb-server.port} accept
      iifname "lo" tcp dport ${toString config.services.memlawb-server.port} accept
    '';
  };
}
