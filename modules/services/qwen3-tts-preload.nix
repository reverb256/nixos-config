# Qwen3-TTS Model Pre-download Service
# Downloads Qwen3-TTS models to HuggingFace cache on first boot
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
  options.services.ai-inference.pre-download = mkEnableOption "Qwen3-TTS model pre-download service";

  config = mkIf cfg.pre-download {
    # Pre-download script using huggingface-cli
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellScriptBin "qwen3-tts-pre-download-script" ''
        #!/usr/bin/env bash
        set -euo pipefail

        CACHE_DIR="/var/cache/ai-inference"
        # Models to download - Tokenizer + main generation models
        MODELS=(
          "Qwen/Qwen3-TTS-Tokenizer-12Hz"
          "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"
          "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice"
        )

        echo "=== Qwen3-TTS Model Pre-Download ==="
        echo "Cache directory: $CACHE_DIR"
        echo ""

        # Create cache directory structure
        mkdir -p "$CACHE_DIR"

        # Set HF_HOME for huggingface-cli
        export HF_HOME="$CACHE_DIR"
        export TRANSFORMERS_CACHE="$CACHE_DIR"
        export HF_HUB_CACHE="$CACHE_DIR/hub"

        echo "Checking for installed models..."
        for model in "''${MODELS[@]}"; do
          model_dir="$CACHE_DIR/hub/models--$(echo $model | tr '/' '--')"

          if [ -d "$model_dir" ] && [ -n "$(ls -A "$model_dir" 2>/dev/null)" ]; then
            echo "✓ $model - already cached"
          else
            echo "⬇ $model - downloading..."
            # Use huggingface-cli from gateway Python environment
            ${config.services.ai-inference.gateway.python}/bin/huggingface-cli download \
              "$model" \
              --local-dir "$CACHE_DIR/$model" \
              --local-dir-use-symlinks False \
              2>&1 || echo "  ✗ Download failed (will retry on next boot)"
          fi
        done

        echo ""
        echo "=== Pre-download complete ==="
        echo "Models cached in: $CACHE_DIR/"
        echo "Total size: $(du -sh $CACHE_DIR 2>/dev/null | cut -f1 || echo 'N/A')"
      '')
    ];

    # Systemd service for one-shot pre-download
    systemd.services.qwen3-tts-pre-download = {
      description = "Pre-download Qwen3-TTS models for instant availability";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      requires = ["network-online.target"];

      serviceConfig = {
        Type = "oneshot";
        User = "ai-inference";
        Group = "ai-inference";
        WorkingDirectory = "/var/cache/ai-inference";
        ExecStart = "${pkgs.qwen3-tts-pre-download-script}/bin/qwen3-tts-pre-download-script";
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
