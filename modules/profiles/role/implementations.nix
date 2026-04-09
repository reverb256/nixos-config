# modules/profiles/role/implementations.nix --- Role profile implementations
{
  config,
  lib,
  ...
}: let
  cfg = config.profiles.role;
in {
  config = lib.mkMerge [
    (lib.mkIf cfg.workstation {
      services.gaming.enable = true;
    })

    (lib.mkIf cfg.gaming {
      services.gaming.enable = true;
    })

    (lib.mkIf cfg.vr {
      services.gaming.vr.enable = true;
    })

    (lib.mkIf cfg.mining {
      services.mining.enable = true;
    })

    (lib.mkIf cfg.aiInference {
      services.ai-inference.enable = true;
      # services.ai-inference.pre-download = true;  # Requires qwen3-tts-preload module
      services.opencode.enable = true;
    })
  ];
}
