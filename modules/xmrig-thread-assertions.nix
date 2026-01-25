{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.mining;
in {
  options.services.mining = {
    xmrig = {
      threads = mkOption {
        type = types.int;
        description = "XMRig thread count - protected per node";
        # Node-specific thread assertions
        apply = value: let
          hostname = config.networking.hostName;
          expectedThreads =
            if hostname == "nexus"
            then 16
            else if hostname == "forge"
            then 12
            else if hostname == "sentry"
            then 8
            else if hostname == "zephyr"
            then 16
            else value; # Default to user value for unknown nodes
        in
          if value != expectedThreads
          then throw "❌ XMRig thread assertion failed!
          Host: ${hostname}
          Expected: ${toString expectedThreads} threads
          Got: ${toString value} threads
          This assertion protects critical mining performance configurations!
          For nexus: 16 threads (16-core system)
          For forge: 12 threads (6-core system with hyperthreading)
          For sentry: 8 threads (8-core system)
          For zephyr: 16 threads (16-core system)"
          else value;
      };
    };
  };

  config = mkIf cfg.enable {
    # Apply the thread assertions
    assertions = [
      {
        assertion =
          if config.networking.hostName == "nexus"
          then cfg.xmrig.threads == 16
          else if config.networking.hostName == "forge"
          then cfg.xmrig.threads == 12
          else if config.networking.hostName == "sentry"
          then cfg.xmrig.threads == 8
          else if config.networking.hostName == "zephyr"
          then cfg.xmrig.threads == 16
          else true;
        message = "❌ XMRig thread count assertion failed!
          Host: ${config.networking.hostName}
          Expected thread counts:
          - nexus: 16 threads (16-core system)
          - forge: 12 threads (6-core system with hyperthreading)
          - sentry: 8 threads (8-core system)
          - zephyr: 16 threads (16-core system)
          This ensures optimal mining performance and prevents revenue loss!";
      }
    ];
  };
}
