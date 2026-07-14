{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.chatterbox-tts;
in {
  options.services.chatterbox-tts = {
    enable = mkEnableOption "Chatterbox TTS — neural TTS server with GPU";

    user = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User to run the container as";
    };

    group = mkOption {
      type = types.str;
      default = "users";
      description = "Group for the voice-refs directory";
    };

    voiceRefsDir = mkOption {
      type = types.path;
      default = "/persistent/voice-refs";
      description = "Directory for reference audio files (voice clones)";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.podman.enable = true;

    # Create voice-refs directory
    systemd.tmpfiles.settings."chatterbox-tts" = {
      "${cfg.voiceRefsDir}" = {
        d = {
          mode = "755";
          user = cfg.user;
          group = cfg.group;
        };
      };
    };

    # Ensure voice-refs directory exists on forge
    systemd.services.chatterbox-tts-setup = {
      description = "Chatterbox TTS — ensure voice-refs directory";
      wantedBy = ["multi-user.target"];
      before = ["chatterbox-tts.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/mkdir -p ${cfg.voiceRefsDir}";
      };
    };

    systemd.services.chatterbox-tts = {
      description = "Chatterbox TTS — neural TTS server (GPU)";
      after = [
        "network-online.target"
        "podman.service"
        "chatterbox-tts-setup.service"
      ];
      wants = [
        "podman.service"
        "network-online.target"
      ];
      wantedBy = ["multi-user.target"];

      path = [pkgs.podman];

      serviceConfig = {
        ExecStart = ''${pkgs.podman}/bin/podman run \
            --name chatterbox-tts \
            --replace \
            --network host \
            --rm \
            -v ${cfg.voiceRefsDir}:/app/reference_audio:Z \
            -e NVIDIA_VISIBLE_DEVICES=all \
            -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
            --device nvidia.com/gpu=all \
            localhost/chatterbox-tts:latest'';
        # Server listens on 8004 inside; host networking exposes on 0.0.0.0:8004

        ExecStop = "${pkgs.podman}/bin/podman stop --ignore chatterbox-tts";

        Restart = "always";
        RestartSec = "5s";

        PrivateTmp = true;
        ProtectSystem = "full";
        ReadWritePaths = [
          cfg.voiceRefsDir
          "/var/lib/containers/storage"
          "/run/podman"
          "/var/lib/containers"
        ];
      };
    };

    # Open port 8004 on the firewall
    networking.firewall.allowedTCPPorts = [8004];
  };
}
