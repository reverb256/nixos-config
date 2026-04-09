# Spacebot Container Image - NixOS dockerTools.buildLayeredImage
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.spacebot;
  inherit (lib) mkOption types mkIf;

  # Spacebot image source (we'll use fetchimage to get the official image)
  spacebotImage = pkgs.dockerTools.pullImage {
    imageName = "ghcr.io/spacedriveapp/spacebot";
    imageDigest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"; # Placeholder - will be updated
    finalImageTag = "latest";
    sha256 = "0000000000000000000000000000000000000000000000000000000000000000"; # Placeholder
  };

  # Runtime dependencies for Spacebot
  spacebotRuntime = pkgs.symlinkJoin {
    name = "spacebot-runtime";
    paths = with pkgs; [
      bash
      coreutils
      curl
      cacert
      # Add Python runtime if Spacebot needs it
      python3
      # Database clients if needed
      sqlite
      # Network tools for debugging
      iputils
      nettools
    ];
  };

  # Container image with all dependencies
  spacebotContainerImage = pkgs.dockerTools.buildLayeredImage {
    name = "spacebot";
    tag = "latest";

    # Include the official Spacebot image and runtime dependencies
    contents = [
      spacebotImage
      spacebotRuntime
    ];

    # Container configuration
    config = {
      # Working directory
      WorkingDir = "/data";

      # Environment variables
      Env = [
        "SPACEBOT_DATA_DIR=/data"
        "PYTHONUNBUFFERED=1"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ];

      # Exposed ports
      ExposedPorts = {
        "19898/tcp" = {};
      };

      # Volume mount points
      Volumes = {
        "/data" = {};
      };

      # Entry point
      Cmd = ["spacebot" "start"];

      # Health check
      HealthCheck = {
        Test = ["CMD" "curl" "-f" "http://localhost:19898/api/health"];
        Interval = 30 * 1000000000; # 30 seconds in nanoseconds
        Timeout = 10 * 1000000000;  # 10 seconds
        Retries = 3;
        StartPeriod = 40 * 1000000000; # 40 seconds
      };

      # User to run as (non-root for security)
      User = "1000:1000";
    };
  };
in {
  options.services.spacebot = {
    enable = mkEnableOption "Spacebot AI Agent Service";

    package = mkOption {
      type = types.package;
      default = spacebotContainerImage;
      description = "Spacebot container image package";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/spacedriveapp/spacebot:latest";
      description = "Spacebot container image reference";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/spacebot";
      description = "Directory for Spacebot data storage";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall ports for Spacebot";
    };
  };

  config = mkIf cfg.enable {
    # Expose the container image for use by Kubernetes
    systemd.services.spacebot-container = {
      description = "Spacebot Container Image Builder";
      serviceConfig.Type = "oneshot";
      # This service just ensures the image is built
      script = "echo 'Spacebot container image: ${spacebotContainerImage}'";
    };

    # Optional: Open firewall if requested
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault (
      lib.optional cfg.openFirewall 19898
    );
  };
}
