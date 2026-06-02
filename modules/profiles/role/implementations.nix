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

    (lib.mkIf cfg.aiInference {
      services.opencode.enable = true;
    })

    (lib.mkIf cfg.monitoring {
      # Monitoring profile: exporters and observability
      # are handled by individual service modules.
      # This role flag is used for node-profiles role assignment only.
    })
  ];
}
