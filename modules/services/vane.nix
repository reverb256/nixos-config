{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.vane;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in {
  options.services.vane = {
    enable = mkEnableOption "Vane AI answering engine";

    port = mkOption {
      type = types.port;
      default = 30900;
      description = "Port for Vane web UI and API";
    };

    searxngUrl = mkOption {
      type = types.str;
      default = "http://10.1.1.120:30888";
      description = "URL of the SearXNG instance to use for web search";
    };

    chatModelUrl = mkOption {
      type = types.str;
      default = "http://10.1.1.140:1235/v1";
      description = "OpenAI-compatible chat model endpoint";
    };

    chatModelKey = mkOption {
      type = types.str;
      default = "Qwen3.5-4B.Q4_K_M.gguf";
      description = "Model key/identifier at the chat endpoint";
    };

    embeddingModelUrl = mkOption {
      type = types.str;
      default = "http://10.1.1.120:8643";
      description = "Embedding model endpoint";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/vane";
      description = "Persistent data directory";
    };

    image = mkOption {
      type = types.str;
      default = "docker.io/itzcrazykns1337/vane:slim-latest";
      description = "Docker image (use slim for external SearXNG)";
    };
  };

  config = mkIf cfg.enable {
    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 vane vane -"
    ];

    # Create system user
    users.users.vane = {
      isSystemUser = true;
      group = "vane";
      home = cfg.dataDir;
    };
    users.groups.vane = {};

    # Podman container
    virtualisation.oci-containers.containers.vane = {
      image = cfg.image;
      autoStart = true;

      ports = ["${toString cfg.port}:3000"];

      volumes = [
        "${cfg.dataDir}:/home/vane/data"
      ];

      environment = {
        SEARXNG_API_URL = cfg.searxngUrl;
      };

      extraOptions = [
        "--network=host"
        "--add-host=host.docker.internal:host-gateway"
        "--health-cmd" "wget --quiet --tries=1 --spider http://localhost:3000 || exit 1"
        "--health-interval" "30s"
        "--health-timeout" "10s"
        "--health-retries" "3"
      ];
    };

    # Firewall
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];
  };
}
