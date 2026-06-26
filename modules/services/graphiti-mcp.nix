{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.graphiti-mcp;
in {
  options.services.graphiti-mcp = {
    enable = mkEnableOption "Graphiti MCP knowledge graph server";

    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Port for the MCP server";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall port";
    };

    openaiApiKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing the OpenAI API key";
    };

    sopsSecret = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ai/openai-api-key";
      description = "Name of a sops-nix secret for the OpenAI API key. Sets openaiApiKeyFile automically.";
    };

    extraPodmanArgs = mkOption {
      type = types.str;
      default = "";
      description = "Extra arguments to pass to podman run";
    };

    image = mkOption {
      type = types.str;
      default = "zepai/knowledge-graph-mcp:latest";
      description = "Graphiti MCP server container image";
    };

    groupId = mkOption {
      type = types.str;
      default = "main";
      description = "Graphiti group ID for namespace isolation";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.podman.enable = true;

    # Resolve sops secret to file path
    sops.secrets = lib.mkIf (cfg.sopsSecret != null) {
      "${cfg.sopsSecret}" = {
        path = "/run/secrets/${builtins.baseNameOf cfg.sopsSecret}";
        format = "binary";
        mode = "0444";
        owner = "j_kro";
        group = "users";
      };
    };

    systemd.services.graphiti-mcp = {
      description = "Graphiti Temporal Knowledge Graph MCP Server";
      after = [ "network.target" "podman.service" ];
      wants = [ "podman.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = let
          resolvedKeyFile = if cfg.sopsSecret != null
            then "/run/secrets/${builtins.baseNameOf cfg.sopsSecret}"
            else cfg.openaiApiKeyFile;
          envArgs = if resolvedKeyFile != null
            then "--env-file ${resolvedKeyFile}"
            else "";
        in "${pkgs.podman}/bin/podman run --rm --name graphiti-mcp -p ${toString cfg.port}:8000 ${envArgs} -e GRAPHITI_GROUP_ID=${cfg.groupId} ${cfg.extraPodmanArgs} ${cfg.image}";
        ExecStop = "${pkgs.podman}/bin/podman stop --ignore graphiti-mcp";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f graphiti-mcp || true";
        Restart = "on-failure";
        RestartSec = "10";
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
