# Boot Emergency Diagnostics System
# Self-contained emergency diagnostics using llama-cpp with local Qwen 3.5 GGUF files
#
# CONCEPT:
# - Separate from AI gateway (independent system)
# - Uses llama-cpp from Nixpkgs with local GGUF models
# - Smart model selection based on emergency type and available resources
# - Self-unloading after diagnostics complete (oneshot service)
# - Leaves behind fix script for manual or automatic execution
#
# Integrates with existing llamafile infrastructure:
# - Uses same llama-cpp package as services.llamafile
# - References existing GGUF models in ~/.lmstudio/models/
# - Compatible with create-llamafile.sh for standalone binaries

{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.boot-emergency-diagnostics;

  # Select llama-cpp variant based on GPU type
  llamaPkg = if cfg.gpu == "amd" || cfg.gpu == "rocm" then pkgs.llama-cpp-rocm
             else if cfg.gpu == "vulkan" then pkgs.llama-cpp-vulkan
             else pkgs.llama-cpp;

  # Emergency type detection (heuristic, not AI)
  detectEmergencyType = pkgs.writeShellScript "detect-emergency" ''
    # Determine emergency type from system state
    # This is fast and deterministic - no LLM needed

    # Check for specific indicators
    if dmesg 2>/dev/null | grep -qi "gpu.*error\|nvidia.*fail"; then
      echo "hardware-gpu"
    elif dmesg 2>/dev/null | grep -qi "i.*error.*mounting\|filesystem.*read-only"; then
      echo "hardware-storage"
    elif systemctl --failed --no-legend 2>/dev/null | grep -qi "nixos\|rebuild"; then
      echo "nixos-build"
    elif systemctl --failed --no-legend 2>/dev/null | grep -qi "garage\|kubernetes\|ai-gateway"; then
      echo "services"
    elif [ $(free -m 2>/dev/null | awk '/^Mem:/{print $2}') -lt 512 ]; then
      echo "memory-low"
    else
      echo "unknown"
    fi
  '';

  # Model selector based on emergency type and available resources
  selectModel = pkgs.writeShellScript "select-model" ''
    EMERGENCY_TYPE="$1"  # hardware-gpu, nixos-build, services, memory-low, unknown
    AVAILABLE_VRAM="$2"   # Free VRAM in MB, or "system" for CPU-only

    # Convert VRAM string to number for comparison
    case "$AVAILABLE_VRAM" in
      system|0)
        AVAILABLE_MB=0
        ;;
      *)
        AVAILABLE_MB="$AVAILABLE_VRAM"
        ;;
    esac

    # Select best model based on emergency type and resources
    case "$EMERGENCY_TYPE" in
      hardware-gpu|hardware-storage)
        if [ "$AVAILABLE_MB" -ge 5120 ]; then
          echo "${cfg.models.capable.name}"
        else
          echo "${cfg.models.quick.name}"
        fi
        ;;

      nixos-build)
        echo "${cfg.models.code.name}"
        ;;

      services)
        echo "${cfg.models.capable.name}"
        ;;

      memory-low)
        echo "${cfg.models.minimal.name}"
        ;;

      unknown)
        # Default to quick for unknown issues
        echo "${cfg.models.quick.name}"
        ;;
    esac
  '';

in {
  options.services.boot-emergency-diagnostics = {
    enable = mkEnableOption "Emergency boot diagnostics with Qwen 3.5 models";

    # Diagnostic model definitions
    models = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Model identifier name";
          };
          ggufPath = mkOption {
            type = types.str;
            description = "Path to local GGUF file";
          };
          vramRequired = mkOption {
            type = types.str;
            description = "VRAM required (e.g., '512M', '2G')";
          };
          ctxSize = mkOption {
            type = types.int;
            default = 2048;
            description = "Context size for the model";
          };
          bestFor = mkOption {
            type = types.listOf types.str;
            description = "Emergency types this is best for";
          };
          gpuLayers = mkOption {
            type = types.int;
            default = 999;
            description = "GPU layers to offload (999 = all, 0 = CPU only)";
          };
        };
      });
      default = {
        # Quick diagnostics - Qwen 3.5 0.8B (~900MB)
        quick = {
          name = "qwen-0.8b";
          ggufPath = "/home/j_kro/.lmstudio/models/unsloth/Qwen3.5-0.8B-GGUF/Qwen3.5-0.8B-Q8_0.gguf";
          vramRequired = "512M";
          ctxSize = 2048;
          bestFor = ["quick" "general" "low-memory"];
          gpuLayers = 999;
        };

        # Code analysis - Qwen 3.5 4B (~2.5GB)
        code = {
          name = "qwen-4b";
          ggufPath = "/home/j_kro/.lmstudio/models/unsloth/Qwen3.5-4B-GGUF/Qwen3.5-4B-IQ4_NL.gguf";
          vramRequired = "2G";
          ctxSize = 4096;
          bestFor = ["nixos" "configuration" "code-analysis"];
          gpuLayers = 999;
        };

        # Capable reasoning - Qwen 3.5 9B (~5.5GB)
        capable = {
          name = "qwen-9b";
          ggufPath = "/home/j_kro/.lmstudio/models/Jackrong/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled-GGUF/Qwen3.5-9B.Q4_K_S.gguf";
          vramRequired = "5G";
          ctxSize = 8192;
          bestFor = ["complex" "multi-step" "hardware"];
          gpuLayers = 999;
        };

        # Minimal fallback - Qwen 3.5 0.8B (CPU-only)
        minimal = {
          name = "qwen-0.8b-minimal";
          ggufPath = "/home/j_kro/.lmstudio/models/unsloth/Qwen3.5-0.8B-GGUF/Qwen3.5-0.8B-Q8_0.gguf";
          vramRequired = "512M";
          ctxSize = 2048;
          bestFor = ["emergency" "fallback" "low-vram"];
          gpuLayers = 0;  # CPU-only for truly minimal
        };
      };
      description = "Available diagnostic models";
    };

    # GPU type for llama-cpp variant selection
    gpu = mkOption {
      type = types.nullOr (types.enum ["nvidia" "amd" "rocm" "vulkan"]);
      default = null;
      description = "GPU type (null = auto-detect, nvidia, amdgpu/rocm, or vulkan)";
    };

    # How to detect available VRAM
    vramDetectionMethod = mkOption {
      type = types.enum ["nvidia-smi" "free" "fixed"];
      default = "nvidia-smi";
      description = "How to detect available VRAM";
    };

    # Fixed VRAM amount (if vramDetectionMethod = "fixed")
    fixedVram = mkOption {
      type = types.int;
      default = 2048;
      description = "Fixed VRAM amount in MB (when detection method is 'fixed')";
    };
  };

  config = mkIf cfg.enable {
    # Install llama-cpp for diagnostics
    environment.systemPackages = [llamaPkg];

    # State directory
    systemd.tmpfiles.rules = [
      "d /var/lib/emergency-diagnostics 0755 root root -"
      "d /var/cache/emergency-diagnostics 0700 root root -"
    ];

    # Emergency detection and diagnostic service
    systemd.services.emergency-diagnostics = {
      description = "Emergency AI diagnostics (Qwen 3.5)";

      # Run early, before most services
      after = ["basic.target"];
      before = [
        "multi-user.target"
        "ai-inference-gateway.service"
      ];
      wantedBy = ["emergency.target"];  # Only run in emergency

      # Only run if there was a boot failure
      conditionPathExists = ["/run/systemd/emergency"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;  # Self-unload after completion

        # Resource limits
        MemoryMax = "8G";  # Enough for 9B model
        CPUQuota = "75%";

        WorkingDirectory = "/var/lib/emergency-diagnostics";

        ExecStart = pkgs.writeShellScript "emergency-diagnostic" ''
          set -euo pipefail

          STATE="/var/lib/emergency-diagnostics"
          CACHE="/var/cache/emergency-diagnostics"
          mkdir -p "$STATE" "$CACHE"

          LOG="$STATE/emergency_$(date +%F_%H%M%S).log"

          echo "=== EMERGENCY DIAGNOSTICS ACTIVATED ===" | tee "$LOG"
          echo "System: $(hostname)" | tee -a "$LOG"
          echo "Time: $(date)" | tee -a "$LOG"
          echo "Uptime: $(uptime)" | tee -a "$LOG"

          # =============================================================================
          # STEP 1: Detect emergency type
          # =============================================================================
          EMERGENCY_TYPE=$(${detectEmergencyType})
          echo "Emergency type: $EMERGENCY_TYPE" | tee -a "$LOG"

          # =============================================================================
          # STEP 2: Detect available resources
          # =============================================================================
          case "${cfg.vramDetectionMethod}" in
            nvidia-smi)
              if command -v nvidia-smi >/dev/null 2>&1; then
                FREE_VRAM=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
                # nvidia-smi returns in MB
                AVAILABLE_VRAM="$${FREE_VRAM:-0}"
              else
                AVAILABLE_VRAM="0"  # No NVIDIA GPU
              fi
              ;;
            free)
              # Use system RAM as fallback (in MB)
              AVAILABLE_VRAM=$(free -m | awk '/^Mem:/{print $2}')
              ;;
            fixed)
              AVAILABLE_VRAM="${toString cfg.fixedVram}"
              ;;
          esac

          echo "Available VRAM/RAM: $AVAILABLE_VRAM MB" | tee -a "$LOG"

          # =============================================================================
          # STEP 3: Select appropriate model
          # =============================================================================
          MODEL_NAME=$(${selectModel} "$EMERGENCY_TYPE" "$AVAILABLE_VRAM")

          # Get model config
          case "$MODEL_NAME" in
            qwen-0.8b)
              MODEL_PATH="${cfg.models.quick.ggufPath}"
              CTX_SIZE="${toString cfg.models.quick.ctxSize}"
              GPU_LAYERS="${toString cfg.models.quick.gpuLayers}"
              ;;
            qwen-4b)
              MODEL_PATH="${cfg.models.code.ggufPath}"
              CTX_SIZE="${toString cfg.models.code.ctxSize}"
              GPU_LAYERS="${toString cfg.models.code.gpuLayers}"
              ;;
            qwen-9b)
              MODEL_PATH="${cfg.models.capable.ggufPath}"
              CTX_SIZE="${toString cfg.models.capable.ctxSize}"
              GPU_LAYERS="${toString cfg.models.capable.gpuLayers}"
              ;;
            qwen-0.8b-minimal)
              MODEL_PATH="${cfg.models.minimal.ggufPath}"
              CTX_SIZE="${toString cfg.models.minimal.ctxSize}"
              GPU_LAYERS="${toString cfg.models.minimal.gpuLayers}"
              ;;
            *)
              echo "Unknown model: $MODEL_NAME" | tee -a "$LOG"
              MODEL_PATH="${cfg.models.minimal.ggufPath}"
              CTX_SIZE="${toString cfg.models.minimal.ctxSize}"
              GPU_LAYERS="0"
              ;;
          esac

          # Verify model exists
          if [ ! -f "$MODEL_PATH" ]; then
            echo "ERROR: Model not found: $MODEL_PATH" | tee -a "$LOG"
            echo "Falling back to minimal diagnostics..." | tee -a "$LOG"
            MODEL_PATH="${cfg.models.minimal.ggufPath}"
            CTX_SIZE="2048"
            GPU_LAYERS="0"
          fi

          echo "Selected model: $MODEL_NAME" | tee -a "$LOG"
          echo "Model path: $MODEL_PATH" | tee -a "$LOG"
          echo "Context size: $CTX_SIZE" | tee -a "$LOG"
          echo "GPU layers: $GPU_LAYERS" | tee -a "$LOG"

          # =============================================================================
          # STEP 4: Gather relevant symptoms (scoped)
          # =============================================================================
          SYMPTOMS="$STATE/symptoms.txt"

          case "$EMERGENCY_TYPE" in
            hardware-gpu|hardware-storage)
              dmesg 2>/dev/null | grep -iE "error|fail" | tail -20 > "$SYMPTOMS" || echo "No hardware errors found" > "$SYMPTOMS"
              ;;
            nixos-build)
              journalctl -u nixos-rebuild --since "1 day ago" --no-pager 2>/dev/null | grep -iE "error|fail" | tail -10 > "$SYMPTOMS" || echo "No nixos-rebuild errors found" > "$SYMPTOMS"
              ;;
            services)
              systemctl --failed --no-legend 2>/dev/null > "$SYMPTOMS" || echo "No service failures" > "$SYMPTOMS"
              echo "" >> "$SYMPTOMS"
              systemctl --failed --no-legend -p 2>/dev/null | head -5 >> "$SYMPTOMS" || true
              ;;
            *)
              journalctl -b -1 --no-pager 2>/dev/null | tail -15 > "$SYMPTOMS" || echo "No journal data available" > "$SYMPTOMS"
              ;;
          esac

          # =============================================================================
          # STEP 5: Run diagnostics with llama-cli
          # =============================================================================
          cat > "$CACHE/prompt.txt" <<EOF
You are an emergency system diagnostic AI specialized in NixOS systems.

Given these boot failure symptoms:

=== SYSTEM STATE ===
$(cat "$SYMPTOMS")

=== HOSTNAME ===
$(hostname)

Identify:
1. Root cause (one line, specific)
2. Fix command (one bash command, or "manual")
3. Confidence (high/medium/low)

Output ONLY this JSON format:
{
  "root_cause": "brief specific description",
  "fix_command": "exact command or 'manual'",
  "confidence": "high|medium|low"
}
EOF

          echo "Running diagnostic model..." | tee -a "$LOG"
          timeout 120s ${llamaPkg}/bin/llama-cli \
            -m "$MODEL_PATH" \
            -ngl "$GPU_LAYERS" \
            -c "$CTX_SIZE" \
            --temp 0 \
            -n 512 \
            -p "$(< "$CACHE/prompt.txt")" \
            2>&1 | tee -a "$LOG" | tee "$CACHE/response.txt"

          # =============================================================================
          # STEP 6: Parse and generate fix script
          # =============================================================================
          FIX_SCRIPT="$STATE/fix_$(date +%H%M%S).sh"

          # Extract JSON (simple parsing, handle various formats)
          RESPONSE=$(cat "$CACHE/response.txt")
          ROOT_CAUSE=$(echo "$RESPONSE" | grep -oP '"root_cause":\s*"\K[^"]+' 2>/dev/null || echo "unknown - check diagnostic log")
          FIX_COMMAND=$(echo "$RESPONSE" | grep -oP '"fix_command":\s*"\K[^"]+' 2>/dev/null || echo "manual")
          CONFIDENCE=$(echo "$RESPONSE" | grep -oP '"confidence":\s*"\K[^"]+' 2>/dev/null || echo "low")

          # Sanitize extracted values (remove control characters, escapes)
          ROOT_CAUSE=$(echo "$ROOT_CAUSE" | tr -d '\n\r' | sed 's/\\n/ /g' | sed 's/\\t/ /g')
          FIX_COMMAND=$(echo "$FIX_COMMAND" | tr -d '\n\r' | sed 's/\\n/ /g' | sed 's/\\t/ /g')

          cat > "$FIX_SCRIPT" <<FIXEOF
#!/bin/bash
# Emergency fix script generated at $(date)
# Emergency type: $EMERGENCY_TYPE
# Root cause: $ROOT_CAUSE
# Model used: $MODEL_NAME
# Confidence: $CONFIDENCE

DIAGNOSTIC_LOG="$LOG"

echo "=== EMERGENCY FIX SCRIPT ==="
echo "Emergency type: $EMERGENCY_TYPE"
echo "Root cause: $ROOT_CAUSE"
echo "Suggested fix: $FIX_COMMAND"
echo "Model: $MODEL_NAME"
echo "Confidence: $CONFIDENCE"
echo ""
echo "Full diagnostic log: $DIAGNOSTIC_LOG"
echo ""

case "$CONFIDENCE" in
  high)
    echo "High confidence - fix can be auto-applied"
    echo ""
    read -p "Execute fix? [y/N/v/d] " choice
    case "$choice" in
      y|Y)
        echo "Executing: $FIX_COMMAND"
        eval "$FIX_COMMAND" || echo "Fix failed - manual intervention required"
        ;;
      v|V)
        echo "Fix command: $FIX_COMMAND"
        ;;
      d|D)
        less "$DIAGNOSTIC_LOG"
        exec "$0"  # Restart menu
        ;;
      *)
        echo "Skipped - fix not applied"
        ;;
    esac
    ;;
  medium)
    echo "Medium confidence - review before executing:"
    echo "$FIX_COMMAND"
    echo ""
    read -p "Execute this fix? [y/N] " answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
      echo "Executing: $FIX_COMMAND"
      eval "$FIX_COMMAND" || echo "Fix failed - manual intervention required"
    fi
    ;;
  low)
    echo "Low confidence - manual intervention recommended"
    echo "Diagnostic log: $DIAGNOSTIC_LOG"
    echo ""
    echo "To view logs: less $DIAGNOSTIC_LOG"
    ;;
esac
FIXEOF

          chmod +x "$FIX_SCRIPT"
          echo "Fix script: $FIX_SCRIPT" | tee -a "$LOG"
          ln -sf "$FIX_SCRIPT" "$STATE/fix.sh"

          # =============================================================================
          # STEP 7: Self-unload
          # =============================================================================
          echo "Diagnostics complete, service unloading..." | tee -a "$LOG"

          # Clean up marker - allow normal boot next time
          rm -f /run/systemd/emergency

          echo "System ready for normal boot or manual intervention" | tee -a "$LOG"
        '';
      };
    };

    # Boot count integration - create emergency marker
    systemd.services.boot-emergency-trigger = {
      description = "Trigger emergency mode on repeated boot failures";
      wantedBy = ["basic.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "check-emergency-trigger" ''
          # Detect rapid reboots (boot loop indicator)
          LAST_BOOT=$(last reboot 2>/dev/null | head -1 | awk '{print $1}' || echo "0")
          CURRENT_BOOT=$(date +%s)
          BOOT_AGE=$((CURRENT_BOOT - LAST_BOOT))

          # If boot is less than 2 minutes old, we're in a boot loop
          if [ "$BOOT_AGE" -lt 120 ] && [ "$BOOT_AGE" -gt 0 ]; then
            echo "Rapid boot detected ($BOOT_AGE seconds) - triggering emergency mode" | wall
            touch /run/systemd/emergency
          fi
        '';
      };
    };

    # Normal boot marker (emergency off)
    systemd.services.boot-normal = {
      description = "Mark normal boot, disable emergency mode";
      after = ["multi-user.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "disable-emergency" ''
          # Remove emergency marker on successful boot
          rm -f /run/systemd/emergency
          echo "Normal boot confirmed - emergency mode disabled" | wall
        '';
      };
    };
  };
}
