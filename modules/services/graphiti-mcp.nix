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
      description = "Path to file containing the raw OpenAI API key";
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

    openaiApiUrl = mkOption {
      type = types.str;
      default = "https://api.z.ai/api/coding/paas/v4";
      description = "OpenAI-compatible API base URL for the LLM provider";
    };

    modelName = mkOption {
      type = types.str;
      default = "glm-4.5";
      description = "Model name for LLM entity extraction";
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

    # Generate env file in proper KEY=VALUE format from raw key file
    systemd.tmpfiles.rules = [
      "d /run/graphiti 0755 root root -"
    ];

    systemd.services.graphiti-mcp = {
      description = "Graphiti Temporal Knowledge Graph MCP Server";
      after = [ "network.target" "podman.service" "sops-nix.service" ];
      wants = [ "podman.service" "sops-nix.service" ];
      wantedBy = [ "multi-user.target" ];

      preStart = let
        resolvedKeyFile = if cfg.sopsSecret != null
          then "/run/secrets/${builtins.baseNameOf cfg.sopsSecret}"
          else cfg.openaiApiKeyFile;
      in lib.optionalString (resolvedKeyFile != null) ''
        if [ -f "${resolvedKeyFile}" ]; then
          echo "OPENAI_API_KEY=$(cat ${resolvedKeyFile} | tr -d '\\n')" > /run/graphiti/env
          chmod 600 /run/graphiti/env
        fi
      '';

      serviceConfig = {
        Type = "simple";
        ExecStart = let
          envFile = "/run/graphiti/env";
        in "${pkgs.podman}/bin/podman run --rm --name graphiti-mcp -p ${toString cfg.port}:8000 --env-file ${envFile} -e GRAPHITI_GROUP_ID=${cfg.groupId} -e OPENAI_API_URL=${cfg.openaiApiUrl} -e MODEL_NAME=${cfg.modelName} ${cfg.extraPodmanArgs} ${cfg.image}";
        ExecStop = "${pkgs.podman}/bin/podman stop --ignore graphiti-mcp";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f graphiti-mcp || true";
        Restart = "on-failure";
        RestartSec = "10";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
