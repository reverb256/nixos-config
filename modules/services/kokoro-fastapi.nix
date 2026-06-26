{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.kokoro-fastapi;
  image = if cfg.useGpu
    then "ghcr.io/remsky/kokoro-fastapi-gpu:latest"
    else "ghcr.io/remsky/kokoro-fastapi-cpu:latest";
in {
  options.services.kokoro-fastapi = {
    enable = mkEnableOption "Kokoro-FastAPI TTS service";

    port = mkOption {
      type = types.port;
      default = 8880;
      description = "Port on which Kokoro-FastAPI will listen";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall port for local network access";
    };

    useGpu = mkOption {
      type = types.bool;
      default = false;
      description = "Use NVIDIA GPU acceleration (requires nvidia-container-toolkit)";
    };

    extraPodmanArgs = mkOption {
      type = types.str;
      default = "";
      description = "Extra arguments to pass to podman run (e.g. --network=host)";
    };

    image = mkOption {
      type = types.str;
      default = image;
      defaultText = literalExpression ''
        if useGpu then "ghcr.io/remsky/kokoro-fastapi-gpu:latest"
        else "ghcr.io/remsky/kokoro-fastapi-cpu:latest"
      '';
      description = "Container image to use";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.podman.enable = true;

    systemd.services.kokoro-fastapi = {
      description = "Kokoro-FastAPI Text-to-Speech Service";
      after = [ "network.target" "podman.service" ];
      wants = [ "podman.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.podman}/bin/podman run --rm --name kokoro-tts -p ${toString cfg.port}:8880 ${cfg.extraPodmanArgs} ${cfg.image}";
        ExecStop = "${pkgs.podman}/bin/podman stop --ignore kokoro-tts";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f kokoro-tts || true";
        Restart = "on-failure";
        RestartSec = "10";
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
