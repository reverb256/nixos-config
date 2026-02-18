{config, lib, pkgs, ...}:
with lib; let
  cfg = config.services.whisper-dictation;
in {
  options.services.whisper-dictation = {
    enable = mkEnableOption "Local Whisper speech-to-text dictation";

    model = mkOption {
      type = types.enum ["tiny.en" "base.en" "small.en" "medium.en" "tiny" "base" "small" "medium"];
      default = "base.en";
      description = "Whisper model. 'base.en' = good balance, 'small.en' = better accuracy.";
    };

    language = mkOption {
      type = types.str;
      default = "en";
      description = "Language code (en, de, fr, etc.)";
    };

    injectionMode = mkOption {
      type = types.enum ["type" "clipboard" "both"];
      default = "type";
      description = ''
        How to inject text:
        - "type": Direct typing via ydotool (works everywhere)
        - "clipboard": Copy to clipboard only
        - "both": Type AND copy to clipboard
      '';
    };

    keyDelay = mkOption {
      type = types.int;
      default = 10;
      description = "Milliseconds between keystrokes";
    };

    silenceTimeout = mkOption {
      type = types.float;
      default = 1.5;
      description = "Seconds of silence before auto-stop (for dictate-auto)";
    };

    silenceThreshold = mkOption {
      type = types.str;
      default = "2%";
      description = "Silence detection threshold (2% = sensitive, 5% = less sensitive). Increase if background noise triggers false stops.";
    };

    notify = mkOption {
      type = types.bool;
      default = true;
      description = "Desktop notifications for dictation events";
    };
  };

  config = mkIf cfg.enable {
    # ==========================================================================
    # YDOTOOLD DAEMON
    # ==========================================================================
    systemd.services.ydotoold = {
      description = "ydotool daemon for virtual input device";
      wantedBy = ["multi-user.target"];
      after = ["systemd-logind.service"];
      
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.ydotool}/bin/ydotoold";
        Restart = "on-failure";
        RestartSec = "2";
        User = "root";
        Group = "root";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = false;
      };
    };

    services.udev.extraRules = ''
      KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
    '';

    users.groups.uinput = {};

    # ==========================================================================
    # WHISPER MODEL
    # ==========================================================================
    systemd.tmpfiles.rules = [
      "d /var/lib/whisper-models 0755 root root - -"
    ];

    systemd.services.whisper-model-download = {
      description = "Download Whisper model if not present";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        MODEL_DIR="/var/lib/whisper-models"
        MODEL_FILE="ggml-${cfg.model}.bin"
        MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_FILE"
        
        if [ ! -f "$MODEL_DIR/$MODEL_FILE" ]; then
          echo "Downloading Whisper model: $MODEL_FILE (~142MB)"
          ${pkgs.curl}/bin/curl -L --progress-bar -o "$MODEL_DIR/$MODEL_FILE" "$MODEL_URL"
        fi
      '';
    };

    # ==========================================================================
    # DICTATION SCRIPTS
    # ==========================================================================
    environment.systemPackages = with pkgs; [
      whisper-cpp
      ydotool
      alsa-utils
      sox
      wl-clipboard
      libnotify
      curl
      procps
    ] ++ [
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
                echo -n "$TEXT" | ${pkgs.wl-clipboard}/bin/wl-copy
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
                  echo -n "$TEXT" | ${pkgs.wl-clipboard}/bin/wl-copy
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
    # SHELL ALIASES
    # ==========================================================================
    programs.bash.shellAliases = {
      dictate = "whisper-dictate";
      "dictate-auto" = "whisper-dictate-auto";
    };

    programs.fish.shellAliases = {
      dictate = "whisper-dictate";
      "dictate-auto" = "whisper-dictate-auto";
    };

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    environment.etc."whisper-dictation/config".text = ''
      WHISPER_MODEL="${cfg.model}"
      WHISPER_LANG="${cfg.language}"
      WHISPER_INJECTION_MODE="${cfg.injectionMode}"
      WHISPER_KEY_DELAY="${toString cfg.keyDelay}"
      WHISPER_SILENCE_TIMEOUT="${toString cfg.silenceTimeout}"
      WHISPER_SILENCE_THRESHOLD="${cfg.silenceThreshold}"
      WHISPER_NOTIFY="${toString cfg.notify}"
    '';

    # ==========================================================================
    # DOCUMENTATION
    # ==========================================================================
    environment.etc."whisper-dictation/README.txt".text = ''
      ╔══════════════════════════════════════════════════════════════╗
      ║           WHISPER DICTATION - LOCAL SPEECH-TO-TEXT          ║
      ╠══════════════════════════════════════════════════════════════╣
      
      COMMANDS
      ──────────────────────────────────────────────────────────────
        dictate          Toggle: Press to START, press again to STOP
        dictate-auto     Auto-stop after silence (VAD detection)
      
      PLASMA SHORTCUT SETUP
      ──────────────────────────────────────────────────────────────
        1. System Settings → Shortcuts → Add Custom Shortcut
        2. Command: whisper-dictate
        3. Shortcut: Meta+D
        
        Usage: Press Meta+D → Speak → Press Meta+D again
      
      AUTO-SILENCE MODE
      ──────────────────────────────────────────────────────────────
        Command: whisper-dictate-auto
        - Starts recording immediately
        - Auto-stops after 1.5s of silence
        - Configure via: silenceTimeout = 2.0
        - If background noise triggers false stops, increase silenceThreshold to "5%" or "10%"
      
      INJECTION MODES
      ──────────────────────────────────────────────────────────────
        type      → Direct typing via ydotool (default)
        clipboard → Copy to clipboard only
        both      → Type AND copy to clipboard
      
      CONFIGURATION (common-base.nix)
      ──────────────────────────────────────────────────────────────
        services.whisper-dictation = {
          enable = true;
          model = "base.en";
          language = "en";
          injectionMode = "type";
          keyDelay = 10;           # ms between keystrokes
          silenceTimeout = 1.5;    # seconds before auto-stop
          silenceThreshold = "5%"; # 2%=sensitive, 5%=balanced, 10%=less sensitive
          notify = true;
        };
      
      SERVICES
      ──────────────────────────────────────────────────────────────
        sudo systemctl start ydotoold
        sudo systemctl start whisper-model-download
      
      ╚══════════════════════════════════════════════════════════════╝
    '';
  };
}
