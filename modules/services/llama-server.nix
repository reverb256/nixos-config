# llama-server systemd service
# Runs llama.cpp server with CUDA-accelerated GGUF models for local LLM inference
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.llama-server;
  inherit (lib) mkEnableOption mkOption types mkIf mkDefault;
in {
  options.services.llama-server = {
    enable = mkEnableOption "llama-server (local LLM inference server)";

    package = mkOption {
      type = types.package;
      default = pkgs.llama-cpp;
      defaultText = "pkgs.llama-cpp";
      description = "llama.cpp package to use";
    };

    # Model selection
    model = mkOption {
      type = types.path;
      example = "/home/j_kro/.lmstudio/models/Jackrong/Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled-GGUF/Qwen3.5-0.8B.Q8_0.gguf";
      description = "Path to GGUF model file";
    };

    # Server configuration
    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Server host address";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Server port";
    };

    # Inference parameters
    ctx-size = mkOption {
      type = types.int;
      default = 8192;
      description = "Context size (tokens)";
    };

    n-gpu-layers = mkOption {
      type = types.int;
      default = 99;  # Offload all layers to GPU by default
      description = "Number of layers to offload to GPU (-1 for all)";
    };

    threads = mkOption {
      type = types.int;
      default = 8;
      description = "Number of CPU threads";
    };

    # Advanced options
    extra-flags = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra flags to pass to llama-server";
    };
  };

  config = mkIf cfg.enable {
    # Create systemd service
    systemd.services.llama-server = {
      description = "llama.cpp LLM inference server";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        ExecStart = lib.concatStringsSep " " (
          [
            (lib.getExe cfg.package)
            "--model" cfg.model
            "--host" cfg.host
            "--port" (toString cfg.port)
            "--ctx-size" (toString cfg.ctx-size)
            "--n-gpu-layers" (toString cfg.n-gpu-layers)
            "--threads" (toString cfg.threads)
            "--metrics"  # Enable Prometheus metrics
            "--log-format" "json"  # Structured logging
          ]
          ++ cfg.extra-flags
        );

        # Restart policy
        Restart = "on-failure";
        RestartSec = 10;

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
       ReadWritePaths = [
          "/tmp"  # For temporary files
        ];

        # Resource limits
        LimitNOFILE = 65536;

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "llama-server";
      };

      # GPU access (NVIDIA)
      environment = {
        CUDA_VISIBLE_DEVICES = "0";  # Use first GPU by default
      };
    };

    # Open firewall for server port
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];
  };
}
