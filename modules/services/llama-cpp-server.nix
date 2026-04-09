# llama.cpp server - OpenAI-compatible API for local GGUF models
# Uses the latest llama.cpp release binary for Gemma 4 support.
# No authentication required - runs on port 1234.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.llama-cpp-server;
in
{
  options.services.llama-cpp-server = {
    enable = lib.mkEnableOption "llama.cpp server for local GGUF inference";

    model = lib.mkOption {
      type = lib.types.str;
      description = "Path to the GGUF model file";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1234;
      description = "Port for the OpenAI-compatible API";
    };

    contextLength = lib.mkOption {
      type = lib.types.int;
      default = 8192;
      description = "Maximum context length in tokens";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User to run the server as";
    };

    alias = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Alias for the model (used as model ID in API)";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments for llama-server";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];

    systemd.services.llama-cpp-server = {
      description = "llama.cpp OpenAI-compatible server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.nvidia-container-toolkit.tools ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStart =
          let
            llamaServer = "${pkgs.llama-cpp}/bin/llama-server";
          in
          ''
            ${llamaServer} \
              --model ${cfg.model} \
              --host 127.0.0.1 \
              --port ${toString cfg.port} \
              --n-gpu-layers -1 \
              --ctx-size ${toString cfg.contextLength} \
              --parallel 4 \
              --cont-batching \
              --metrics \
              ${lib.optionalString (cfg.alias != null) "--alias ${cfg.alias}"} \
              ${lib.escapeShellArgs cfg.extraArgs}
          '';
        Restart = "on-failure";
        RestartSec = "5s";
        # Clear LD_LIBRARY_PATH to prevent host libggml (nixpkgs v8401) from
        # conflicting with our bundled version (b8724). Nix RPATH finds the right libs.
        Environment = "LD_LIBRARY_PATH=";
      };
    };
  };
}
