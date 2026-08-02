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
      services.mining.enable = lib.mkDefault true;
    })

    (lib.mkIf cfg.aiInference {
      # 2026-08-02: NixOS-side services.ai-inference gateway REMOVED — it
      # pulled the torch/sentence-transformers stack into every host closure
      # (ROCm source builds; blocked sentry deploy). The gateway runs in K8s
      # from a prebuilt image (nexus:5000/ai-inference-gateway). OpenCode
      # keeps using the K8s gateway via nodePort.
      services.opencode.enable = true;
    })
  ];
}
