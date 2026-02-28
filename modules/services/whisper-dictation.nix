{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.whisper-dictation;
in {
  # ==========================================================================
  # MODULE OPTIONS
  # ==========================================================================
  options.services.whisper-dictation = with lib; {
    enable =
      lib.mkEnableOption "Enable Whisper Dictation (speech-to-text)"
      // {
        default = false;
        description = "Local Whisper speech-to-text with KDE Plasma integration";
        type = lib.types.bool;
      };

    model = lib.mkOption {
      type = lib.types.str;
      default = "base.en";
      description = "Whisper model to use (e.g., base.en, tiny.en, small.en)";
      example = "base.en";
    };

    language = lib.mkOption {
      type = lib.types.str;
      default = "en";
      description = "Transcription language";
      example = "en";
    };

    injectionMode = lib.mkOption {
      type = lib.types.enum ["type" "clipboard" "both"];
      default = "type";
      description = "How to inject transcribed text (type, clipboard, both)";
      example = "type";
    };

    keyDelay = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Delay between keystrokes in milliseconds (for type injection)";
      example = 10;
    };

    notify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show KDE notification after transcription";
      example = true;
    };

    silenceTimeout = lib.mkOption {
      type = lib.types.float;
      default = 1.5;
      description = "Auto-stop after N seconds of silence (whisper-dictate-auto only)";
      example = 1.5;
    };

    silenceThreshold = lib.mkOption {
      type = lib.types.str;
      default = "2%";
      description = "Silence threshold (2%=sensitive, 5%=balanced, 10%=less sensitive)";
      example = "5%";
    };

    sessionVariables = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Environment variables to set for Whisper process";
      example = ["WHISPER_MODEL_PATH=/path"];
    };
  };

  # ==========================================================================
  # CONFIGURATION
  # ==========================================================================
  config = mkIf cfg.enable {
    # ==========================================================================
    # DICTATION SCRIPTS
    # ==========================================================================
    environment.systemPackages = with pkgs;
      [
        whisper-cpp
        ydotool
        alsa-utils
        sox
        wl-clipboard-rs
        libnotify
        curl
        procps
      ]
      ++ [
        # ========================================================================
        # whisper-dictate: Toggle mode (press to start/stop)
        # ========================================================================
        (pkgs.writeShellScriptBin "whisper-dictate" ''
          set -euo pipefail

          MODEL_DIR="/var/lib/whisper-models"
          MODEL_FILE="ggml-${cfg.model}.bin"
          MODEL_PATH="$MODEL_DIR/$MODEL_FILE"
          PID_FILE="/tmp/whisper-dictate.pid"
          RECORDING="/tmp/whisper-dictate.wav"
          OUTPUT="/tmp/whisper-output"
          INJECTION_MODE="${cfg.injectionMode}"
          KEY_DELAY="${toString cfg.keyDelay}"

          # Transcribe and inject function
          transcribe_and_inject() {
            if [ ! -s "$RECORDING" ]; then
              ${optionalString cfg.notify ''${pkgs.libnotify}/bin/notify-send "Whisper" "No audio recorded" --icon=dialog-warning''}
              return 1
            fi

            ${optionalString cfg.notify ''${pkgs.libnotify}/bin/notify-send "⏳ Whisper" "Transcribing..." --icon=preferences-desktop-locale''}

            ${pkgs.whisper-cpp}/bin/whisper-cpp \
              -m "$MODEL_PATH" \
              -l ${cfg.language} \
              -f "$RECORDING" \
              -otxt \
              -of "$OUTPUT" \
              --no-prints \
              2>/dev/null || true

            if [ ! -f "$OUTPUT.txt" ]; then
              ${optionalString cfg.notify ''${pkgs.libnotify}/bin/notify-send "Whisper" "Transcription failed" --icon=dialog-error''}
              return 1
            fi

            TEXT=$(cat "$OUTPUT.txt" | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            if [ -z "$TEXT" ]; then
              ${optionalString cfg.notify ''${pkgs.libnotify}/bin/notify-send "Whisper" "No speech detected" --icon=dialog-warning''}
              return 0
            fi

            echo "$TEXT"

            case "$INJECTION_MODE" in
              type|both)
                ${pkgs.ydotool}/bin/ydotool type --key-delay "$KEY_DELAY" -- "$TEXT"
                ;;
            esac

            case "$INJECTION_MODE" in
              clipboard|both)
                if [ -n "$WAYLAND_DISPLAY" ]; then
                  echo -n "$TEXT" | /run/current-system/sw/bin/wl-copy-rs
                elif [ -n "$DISPLAY" ]; then
                  echo -n "$TEXT" | ${pkgs.xclip}/bin/xclip -selection clipboard 2>/dev/null || true
                fi
                ;;
            esac

            ${optionalString cfg.notify ''${pkgs.libnotify}/bin/notify-send "✅ Whisper" "$TEXT" --icon=edit-paste''}
          }

          # Check model
          if [ ! -f "$MODEL_PATH" ]; then
            echo "Model not found. Run: sudo systemctl start whisper-model-download"
            ${optionalString cfg.notify ''${pkgs.libnotify}/bin/notify-send "Whisper" "Model not downloaded" --icon=dialog-error''}
            exit 1
          fi

          # Check ydotoold
          if ! pgrep -x "ydotoold" > /dev/null; then
            sudo systemctl start ydotoold 2>/dev/null || true
            sleep 0.3
          fi

          # TOGGLE LOGIC
          if [ -f "$PID_FILE" ]; then
            OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")

            if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
              # Stop recording
              kill "$OLD_PID" 2>/dev/null || true
              rm -f "$PID_FILE"

              # Wait for recording to finalize
              sleep 0.2

              # Transcribe
              transcribe_and_inject

              # Cleanup
              rm -f "$RECORDING" "$OUTPUT.txt" "$OUTPUT.json"
              exit 0
            fi
          fi

          # Start recording
          rm -f "$RECORDING" "$OUTPUT.txt" "$OUTPUT.json"

          ${optionalString cfg.notify ''${pkgs.libnotify}/bin/notify-send "🎤 Whisper" "Recording... Press shortcut again to stop" --icon=audio-input-microphone''}

          ${pkgs.alsa-utils}/bin/arecord -f cd -t wav "$RECORDING" 2>/dev/null &
          RECORD_PID=$!
          echo "$RECORD_PID" > "$PID_FILE"

          wait $RECORD_PID 2>/dev/null || true
          rm -f "$PID_FILE"
        '')

        # ========================================================================
        # whisper-dictate-auto: Auto-stop on silence (VAD)
        # ========================================================================
        (pkgs.writeShellScriptBin "whisper-dictate-auto" ''
          set -euo pipefail

          MODEL_DIR="/var/lib/whisper-models"
          MODEL_FILE="ggml-${cfg.model}.bin"
          MODEL_PATH="$MODEL_DIR/$MODEL_FILE"
          RECORDING="/tmp/whisper-auto-$$.wav"
          OUTPUT="/tmp/whisper-auto-$$"
          INJECTION_MODE="${cfg.injectionMode}"
          KEY_DELAY="${toString cfg.keyDelay}"
          SILENCE="${toString cfg.silenceTimeout}"
          SILENCE_THRESHOLD="${cfg.silenceThreshold}"

          cleanup() {
            rm -f "$RECORDING" "$OUTPUT.txt" "$OUTPUT.json" 2>/dev/null || true
          }
          trap cleanup EXIT

          if [ ! -f "$MODEL_PATH" ]; then
            echo "Model not found. Run: sudo systemctl start whisper-model-download"
            ${optionalString cfg.notify ''${pkgs.libnotify}/bin/notify-send "Whisper" "Model not downloaded" --icon=dialog-error''}
            exit 1
          fi

          if ! pgrep -x "ydotoold" > /dev/null; then
            sudo systemctl start ydotoold 2>/dev/null || true
            sleep 0.3
          fi

          ${optionalString cfg.notify ''${pkgs.libnotify}/bin/notify-send "🎤 Whisper" "Speak now - auto-stops after ${toString cfg.silenceTimeout}s silence" --icon=audio-input-microphone''}
          echo "🎤 Recording... Will auto-stop after ${toString cfg.silenceTimeout}s of silence"

          # Record with sox silence detection
          # silence 1: above_periods=1, duration=0.5s, threshold=$SILENCE_THRESHOLD (start when audio detected)
          # silence 2: below_periods=1, duration=$SILENCE, threshold=$SILENCE_THRESHOLD (stop after silence)
          ${pkgs.sox}/bin/sox -t alsa default -t wav "$RECORDING" \
            silence 1 0.5 ${cfg.silenceThreshold} 1 "$SILENCE" ${cfg.silenceThreshold} 2>/dev/null || {
              # Fallback to arecord if sox fails
              ${pkgs.alsa-utils}/bin/arecord -f cd -t wav -d 30 "$RECORDING" 2>/dev/null
            }

          ${optionalString cfg.notify ''${pkgs.libnotify}/bin/notify-send "⏳ Whisper" "Transcribing..." --icon=preferences-desktop-locale''}

          ${pkgs.whisper-cpp}/bin/whisper-cpp \
            -m "$MODEL_PATH" \
            -l ${cfg.language} \
            -f "$RECORDING" \
            -otxt \
            -of "$OUTPUT" \
            --no-prints \
            2>/dev/null || true

          if [ -f "$OUTPUT.txt" ]; then
            TEXT=$(cat "$OUTPUT.txt" | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            if [ -n "$TEXT" ]; then
              echo "$TEXT"

              case "$INJECTION_MODE" in
                type|both)
                  ${pkgs.ydotool}/bin/ydotool type --key-delay "$KEY_DELAY" -- "$TEXT"
                  ;;
              esac

              case "$INJECTION_MODE" in
                clipboard|both)
                  if [ -n "$WAYLAND_DISPLAY" ]; then
                    echo -n "$TEXT" | ${pkgs.wl-clipboard-rs}/bin/wl-copy
                  elif [ -n "$DISPLAY" ]; then
                    echo -n "$TEXT" | ${pkgs.xclip}/bin/xclip -selection clipboard 2>/dev/null || true
                  fi
                  ;;
              esac

              ${optionalString cfg.notify ''${pkgs.libnotify}/bin/notify-send "✅ Whisper" "$TEXT" --icon=edit-paste''}
            else
              ${optionalString cfg.notify ''${pkgs.libnotify}/bin/notify-send "Whisper" "No speech detected" --icon=dialog-warning''}
            fi
          fi
        '')
      ];

    # ==========================================================================
    # SYSTEMD SERVICES
    # ==========================================================================
    systemd.services.ydotoold = {
      description = "YDotoold - ydotool daemon for keyboard input injection";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = "root";
        ExecStart = "${pkgs.ydotool}/bin/ydotoold";
        Restart = "on-failure";
        RestartSec = 5;

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateDevices = false;  # Required for /dev/uinput access
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = ["AF_UNIX"];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        CapabilityBoundingSet = "";
        SystemCallArchitectures = "native";
      };
    };

    systemd.services.whisper-model-download = {
      description = "Download Whisper model";
      path = [pkgs.curl pkgs.coreutils];
      script = ''
        MODEL_DIR="/var/lib/whisper-models"
        MODEL_FILE="ggml-${cfg.model}.bin"
        MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_FILE"

        mkdir -p "$MODEL_DIR"
        cd "$MODEL_DIR"

        if [ ! -f "$MODEL_FILE" ]; then
          echo "Downloading $MODEL_FILE..."
          curl -L -o "$MODEL_FILE" "$MODEL_URL"
          echo "Downloaded to $MODEL_DIR/$MODEL_FILE"
        else
          echo "Model already exists at $MODEL_DIR/$MODEL_FILE"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        CapabilityBoundingSet = "";
        SystemCallArchitectures = "native";

        # Resource limits
        MemoryMax = "512M";
      };
    };
  };
}
