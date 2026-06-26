{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.chatterbox-tts;
in {
  options.services.chatterbox-tts = {
    enable = mkEnableOption "Chatterbox-TTS Server (multi-engine, OpenAI-compatible)";

    port = mkOption {
      type = types.port;
      default = 8004;
      description = "Port on which Chatterbox will listen";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall port for local network access";
    };

    gpuIndex = mkOption {
      type = types.int;
      default = 0;
      description = "NVIDIA GPU index to use (via CUDA_VISIBLE_DEVICES)";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/chatterbox-tts";
      description = "Directory for repo clone, config, voices, and model cache";
    };

    extraPodmanArgs = mkOption {
      type = types.str;
      default = "";
      description = "Extra arguments to pass to podman run";
    };
  };

  config = mkIf cfg.enable {
    # Enable nvidia-container-toolkit for GPU passthrough
    hardware.nvidia-container-toolkit = {
      enable = true;
      mount-nvidia-executables = true;
    };

    virtualisation.podman.enable = true;

    systemd.services.chatterbox-tts = {
      description = "Chatterbox-TTS Server";
      after = [ "network.target" "podman.service" ];
      wants = [ "podman.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        CUDA_VISIBLE_DEVICES = toString cfg.gpuIndex;
        HOME = cfg.dataDir;
      };

      serviceConfig = {
        Type = "simple";
        User = "root";
        Restart = "on-failure";
        RestartSec = "15";
        TimeoutStartSec = "600"; # Build can take a while
        TimeoutStopSec = "60";

        # Clone repo if not present, then build container image
        ExecStartPre = [
          (pkgs.writeShellScript "chatterbox-setup" ''
            set -euo pipefail
            mkdir -p "${cfg.dataDir}"
            if [ ! -d "${cfg.dataDir}/Chatterbox-TTS-Server" ]; then
              ${pkgs.git}/bin/git clone \
                https://github.com/devnen/Chatterbox-TTS-Server.git \
                "${cfg.dataDir}/Chatterbox-TTS-Server"
            fi
            for d in voices reference_audio outputs logs; do
              mkdir -p "${cfg.dataDir}/$d"
            done
            cd "${cfg.dataDir}/Chatterbox-TTS-Server"
            if ! ${pkgs.podman}/bin/podman image exists chatterbox-tts:latest 2>/dev/null; then
              ${pkgs.podman}/bin/podman build -t chatterbox-tts:latest \
                -f Dockerfile --build-arg RUNTIME=nvidia . \
                || echo "WARNING: image build failed, will try to use pre-built if available"
            fi
          '')
        ];

        ExecStart = "${pkgs.bash}/bin/bash -c 'cd ${cfg.dataDir}/Chatterbox-TTS-Server && ${pkgs.podman}/bin/podman run --rm --name chatterbox-tts -p ${toString cfg.port}:8004 --device nvidia.com/gpu=all -v ${cfg.dataDir}/config.yaml:/app/config.yaml -v ${cfg.dataDir}/voices:/app/voices -v ${cfg.dataDir}/reference_audio:/app/reference_audio -v ${cfg.dataDir}/outputs:/app/outputs -v ${cfg.dataDir}/logs:/app/logs -v chatterbox-hf-cache:/app/hf_cache ${cfg.extraPodmanArgs} chatterbox-tts:latest'";

        ExecStop = "${pkgs.podman}/bin/podman stop --ignore chatterbox-tts";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f chatterbox-tts || true";
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
