# Bonsai 27B llama-server deployments
#
# Replaces existing inference endpoints with PrismML Bonsai 27B models:
#   - Zephyr RTX 3090 (GPU 1): Ternary-Bonsai-27B (Q2_0, 6.7 GB) on port 1237
#   - Forge RTX 4060 (GPU 0): 1-bit Bonsai-27B (Q1_0, 3.6 GB) on port 8002
#   - Sentry AMD 5600 XT: 1-bit Bonsai-27B via Vulkan on port 8003
#
# Build from PrismML fork: nix build .#cuda on the prism branch
# Models: /models/bonsai/{ternary-27b,1bit-27b}
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.bonsai;
in {
  options.services.bonsai = {
    enable = mkEnableOption "Bonsai 27B llama-server inference";

    package = mkOption {
      type = types.package;
      description = "PrismML llama.cpp package (llama-server binary)";
    };

    ternaryModel = mkOption {
      type = types.path;
      default = "/models/bonsai/ternary-27b/Ternary-Bonsai-27B-Q2_0.gguf";
    };

    onebitModel = mkOption {
      type = types.path;
      default = "/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
    };

    dsparkModel = mkOption {
      type = types.nullOr types.path;
      default = "/models/bonsai/dspark/Ternary-Bonsai-27B-dspark-Q4_1.gguf";
    };

    mmproj = mkOption {
      type = types.nullOr types.path;
      default = "/models/bonsai/ternary-27b/Ternary-Bonsai-27B-mmproj-Q8_0.gguf";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.bonsai-ternary-zephyr = {
      description = "Bonsai 27B Ternary — Zephyr RTX 3090 (port 1237)";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${getExe cfg.package} -m ${cfg.ternaryModel} --host 0.0.0.0 --port 1237 -ngl 99 -fa on -c 0 --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 --jinja --alias ternary-bonsai-27b${lib.optionalString (cfg.mmproj != null) " --mmproj ${cfg.mmproj}"}";
        Restart = "on-failure";
        RestartSec = "10";
        StandardOutput = "journal";
        StandardError = "journal";
        OOMScoreAdjust = 500;
      };

      environment = {
        CUDA_VISIBLE_DEVICES = "1"; # RTX 3090
      };
    };

    systemd.services.bonsai-1bit-forge = {
      description = "Bonsai 27B 1-bit — Forge RTX 4060 (port 8002)";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${getExe cfg.package} -m ${cfg.onebitModel} --host 0.0.0.0 --port 8002 -ngl 99 -fa on -c 0 --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 --alias bonsai-27b-1bit";
        Restart = "on-failure";
        RestartSec = "10";
        StandardOutput = "journal";
        StandardError = "journal";
        OOMScoreAdjust = 500;
      };

      environment = {
        CUDA_VISIBLE_DEVICES = "0";
      };
    };
  };
}
