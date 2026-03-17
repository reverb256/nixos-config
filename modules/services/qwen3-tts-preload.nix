# Qwen3-TTS Model Pre-download Service
# Downloads Qwen3-TTS models on first boot for instant availability
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ai-inference;
  inherit (lib) mkEnableOption mkIf mkOption types literalExpression;

in
{
  options.services.ai-inference.pre-download = mkEnableOption "Qwen3-TTS model pre-download service" {
    description = "Download Qwen3-TTS models in background during first boot";
    default = false;
  };

  config = mkIf cfg.pre-download {
    # Pre-download script
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellScriptBin "qwen3-tts-pre-download" ''
        #!/usr/bin/env bash
        set -euo pipefail

        CACHE_DIR="/var/cache/ai-inference"
        MODELS=(
          "Qwen/Qwen3-TTS-Tokenizer-12Hz"
          "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"
          "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice"
        )

        echo "=== Qwen3-TTS Model Pre-Download ==="
        echo "Cache directory: $CACHE_DIR"
        echo ""

        # Create cache directory
        mkdir -p "$CACHE_DIR/hub"

        # Run as ai-inference user if available, otherwise current user
        RUN_AS="ai-inference"
        if ! id "$RUN_AS" &>/dev/null; then
          RUN_AS="root"
        fi

        echo "Checking for installed models..."
        for model in "''${MODELS[@]}"; do
          model_dir="$CACHE_DIR/hub/models--$(echo $model | tr '/' '--')"

          if [ -d "$model_dir" ] && [ -n "$(ls -A "$model_dir" 2>/dev/null)" ]; then
            echo "✓ $model - already cached"
          else
            echo "⬇ $model - downloading..."
            # Use qwen-tts Python package to download model
            # This uses HuggingFace under the hood
            su - "$RUN_AS" -c "
              PYTHONPATH=${config.services.ai-inference.gateway.python}:$PYTHONPATH \\
              TRANSFORMERS_CACHE=$CACHE_DIR \\
              HF_HOME=$CACHE_DIR \\
              python3 -c '
import torch
from qwen_tts import Qwen3TTSModel

print(f\"Loading model: $model...\")
model = Qwen3TTSModel.from_pretrained(
    \"$model\",
    device_map=\"cpu\",
    dtype=torch.float16,
)
print(\"Model loaded successfully!\")
' 2>&1 || echo "  ✗ Download failed (check internet connection)"
          fi
        done

        echo ""
        echo "=== Pre-download complete ==="
        echo "Models cached in: $CACHE_DIR/hub/"
        echo "Total size: $(du -sh $CACHE_DIR/hub 2>/dev/null | cut -f1 || echo 'N/A')"
      '')
    ];

    # Systemd service for one-shot pre-download
    systemd.services.qwen3-tts-pre-download = {
      description = "Pre-download Qwen3-TTS models for instant availability";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "ai-inference-gateway.service"];
      # Don't fail if gateway isn't available yet
      requires = ["network-online.target"];

      serviceConfig = {
        Type = "oneshot";
        User = "ai-inference";
        Group = "ai-inference";
        WorkingDirectory = "/var/cache/ai-inference";
        ExecStart = "${pkgs.qwen3-tts-pre-download}/bin/qwen3-tts-pre-download";
        # Don't fail if pre-download fails (models will download on first use)
        RemainAfterExit = "no";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "qwen3-tts-pre-download";
      };
    };

    # Timer to run pre-download after system is stable
    systemd.timers.qwen3-tts-pre-download = {
      description = "Trigger Qwen3-TTS pre-download after boot";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnActiveSec = "5min";  # Run 5 minutes after boot
        AccuracySec = "1h";    # Retry within 1 hour if missed
        Persistent = "true";  # Run even if previous run was missed
      };
    };
  };
}
