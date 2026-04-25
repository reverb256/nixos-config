{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.voxtype;
in
with lib;
{
  options.services.voxtype = {
    enable = mkEnableOption "Enable voxtype (push-to-talk voice dictation for Wayland)" // {
      default = false;
      description = "Push-to-talk voice dictation using whisper.cpp with PTT on Niri";
    };

    model = mkOption {
      type = types.str;
      default = "base.en";
      description = "Whisper model (e.g., tiny.en, base.en, small.en)";
      example = "base.en";
    };

    language = mkOption {
      type = types.str;
      default = "en";
      description = "Language code for transcription";
      example = "en";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      voxtype-vulkan
      wtype
      wl-clipboard
      vulkan-loader
    ];

    environment.sessionVariables = {
      VOXTYPE_VULKAN_DEVICE = "nvidia";
    };

    systemd.services.voxtype-model-download = {
      description = "Download voxtype whisper model";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeScript "voxtype-download-model" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail
          MODEL_DIR="/home/j_kro/.config/voxtype/models"
          mkdir -p "$MODEL_DIR"
          cd "$MODEL_DIR"
          MODEL_FILE="ggml-${cfg.model}.bin"
          if [ ! -f "$MODEL_FILE" ]; then
            echo "Downloading whisper model ${cfg.model}..."
            ${pkgs.curl}/bin/curl -L -o "$MODEL_FILE" \
              "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_FILE"
            echo "Downloaded to $MODEL_DIR/$MODEL_FILE"
          else
            echo "Model already exists"
          fi
        '';
      };
    };
  };
}
