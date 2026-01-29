{ config, lib, pkgs, ... }:
let
  cfg = config.services.opencode;
in
{
  options.services.opencode = {
    enable = lib.mkEnableOption "Enable OpenCode configuration";

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "minimax/minimax-m2.1:free";
      description = "Default model for OpenCode agents";
    };

    providers = lib.mkOption {
      type = lib.types.attrs;
      default = {
        kilocode = {
          baseURL = "https://api.kilocode.ai/v1";
          apiKey = null; # Set via secrets
        };
        streamlake = {
          baseURL = "https://vanchin.streamlake.ai/api/gateway/coding/v1";
          apiKey = null; # Set via secrets
        };
      };
      description = "OpenCode provider configurations";
    };
  };

  config = lib.mkIf cfg.enable {
    # OpenCode configuration files
    xdg.configFile."opencode/opencode.json" = {
      force = true;
      text = builtins.toJSON {
        plugin = [ "oh-my-opencode" ];
        "$schema" = "https://opencode.ai/config.json";
        model = cfg.defaultModel;
        provider = {
          kilocode = {
            options = {
              baseURL = cfg.providers.kilocode.baseURL;
              apiKey = cfg.providers.kilocode.apiKey or "kilocode-token";
            };
            models = {
              "minimax-minimax-m2.1-free" = {
                name = "minimax/minimax-m2.1:free";
              };
            };
          };
          streamlake = {
            options = {
              baseURL = cfg.providers.streamlake.baseURL;
              apiKey = cfg.providers.streamlake.apiKey or "streamlake-token";
            };
            models = {
              "kat-coder-pro-v1" = {
                name = "kat-coder-pro-v1";
              };
            };
          };
        };
        agent = {
          sisyphus = { model = cfg.defaultModel; };
          librarian = { model = cfg.defaultModel; };
          explore = { model = cfg.defaultModel; };
          oracle = { model = cfg.defaultModel; };
          "frontend-ui-ux-engineer" = { model = cfg.defaultModel; };
          "document-writer" = { model = cfg.defaultModel; };
          "multimodal-looker" = { model = cfg.defaultModel; };
        };
      };
    };

    xdg.configFile."opencode/oh-my-opencode.json" = {
      force = true;
      text = builtins.toJSON {
        "$schema" = "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/master/assets/oh-my-opencode.schema.json";
        agents = {
          sisyphus = { model = cfg.defaultModel; };
          librarian = { model = cfg.defaultModel; };
          explore = { model = cfg.defaultModel; };
          oracle = { model = cfg.defaultModel; };
          "frontend-ui-ux-engineer" = { model = cfg.defaultModel; };
          "document-writer" = { model = cfg.defaultModel; };
          "multimodal-looker" = { model = cfg.defaultModel; };
        };
      };
    };

    # Environment variables for OpenCode
    home.sessionVariables = {
      OPENCODE_MCP_SCHEMA_FIX = "1";
      OPENCODE_TOOL_STRUCTURED_OUTPUT = "1";
      OPENCODE_PATH_FIX = "1";
    };
  };
}
