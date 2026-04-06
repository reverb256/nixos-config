# Spacebot Container Module - Kubernetes/Nix-native builds
# This module provides dockerTools.buildLayeredImage for K8s deployment
# Note: The main systemd/Podman service is in ../spacebot.nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;

  # Nix-built Spacebot container image
  # This uses dockerTools.buildLayeredImage for reproducible builds
  spacebotContainerImage = pkgs.dockerTools.buildLayeredImage {
    name = "spacebot-nixos";
    tag = "latest";

    # Include minimal runtime dependencies
    contents = with pkgs; [
      bash
      coreutils
      curl
      cacert
      python3
    ];

    config = {
      WorkingDir = "/data";
      Cmd = [
        "spacebot"
        "start"
      ];
      Env = [
        "SPACEBOT_DATA_DIR=/data"
        "PYTHONUNBUFFERED=1"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ];
      ExposedPorts = {
        "19898/tcp" = { };
      };
      Volumes = {
        "/data" = { };
      };
      User = "1000:1000";
    };
  };
in
{
  options.services.spacebot-container = {
    enable = mkEnableOption "Spacebot container image builder";

    image = mkOption {
      type = types.package;
      default = spacebotContainerImage;
      description = "Spacebot container image package";
    };
  };

  config = mkIf config.services.spacebot-container.enable {
    # Expose the container image for Kubernetes
    systemd.services.spacebot-container-builder = {
      description = "Spacebot Container Image Builder";
      serviceConfig.Type = "oneshot";
      script = "echo 'Spacebot container image: ${spacebotContainerImage}'";
    };

    # Pre-seed the image to containerd for Kubernetes use
    # Note: k3s manages kubelet internally, so we seed via containerd directly
    virtualisation.containerd.enable = true;
    systemd.services.spacebot-seed = {
      description = "Pre-seed spacebot container image to containerd";
      wantedBy = [ "multi-user.target" ];
      after = [ "containerd.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.podman}/bin/podman image pull ${spacebotContainerImage} 2>/dev/null || true
      '';
    };
  };
}
