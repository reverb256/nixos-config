{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.supermemory;
in {
  options.services.supermemory = {
    enable = lib.mkEnableOption "Supermemory local memory engine";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/home/j_kro/.supermemory";
      description = "Data directory for Supermemory";
    };

    openaiBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://sentry.lan:1235/v1";
      description = "OpenAI-compatible API URL (local llama-server)";
    };

    openaiApiKey = lib.mkOption {
      type = lib.types.str;
      default = "sk-dummy-key";
      description = "API key for OpenAI-compatible endpoint (dummy for local)";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "Qwen3.5-4B-Q4_K_M.gguf";
      description = "Model name for fact extraction";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6767;
      description = "Port to serve Supermemory API on";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User to run Supermemory as";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.supermemory = {
      description = "Supermemory local memory engine";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];

      environment = {
        SUPERMEMORY_DATA_DIR = cfg.dataDir;
        SUPERMEMORY_OPENAI_BASE_URL = cfg.openaiBaseUrl;
        SUPERMEMORY_OPENAI_API_KEY = cfg.openaiApiKey;
        SUPERMEMORY_MODEL = cfg.model;
        SUPERMEMORY_PORT = toString cfg.port;
      };

      serviceConfig = {
        User = cfg.user;
        Group = "users";
        ExecStart = "${pkgs.nodejs}/bin/node ${cfg.dataDir}/bin/supermemory-server";
        Restart = "on-failure";
        RestartSec = "5s";
        WorkingDirectory = cfg.dataDir;
      };
    };

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}