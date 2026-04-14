{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.ai-inference;
  inherit (lib) mkEnableOption mkIf;

  preDownloadScript = pkgs.writeShellScriptBin "qwen3-tts-pre-download" ''
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

    mkdir -p "$CACHE_DIR"

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
  '';
in {
  options.services.ai-inference.pre-download = mkEnableOption "Qwen3-TTS model pre-download service";

  config = mkIf cfg.pre-download {
    environment.systemPackages = [preDownloadScript];

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
        ExecStart = "${preDownloadScript}/bin/qwen3-tts-pre-download";
        RemainAfterExit = "no";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "qwen3-tts-pre-download";
      };
    };

    systemd.timers.qwen3-tts-pre-download = {
      description = "Trigger Qwen3-TTS pre-download after boot";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnActiveSec = "5min";
        AccuracySec = "1h";
        Persistent = "true";
      };
    };
  };
}
