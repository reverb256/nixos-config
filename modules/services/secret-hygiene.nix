{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.secret-hygiene;
  inherit
    (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;
in {
  options.services.secret-hygiene = {
    enable = mkEnableOption "Monthly secret hygiene scanning and session cleanup for agent sessions";

    user = mkOption {
      type = types.str;
      default = "j_kro";
      description = "Owner of the agent session directories";
    };

    homeDir = mkOption {
      type = types.path;
      default = "/home/j_kro";
      description = "Home directory of the agent user";
    };

    scanScript = mkOption {
      type = types.path;
      default = "/home/j_kro/.hermes/skills/devops/agent-session-secret-hygiene/scripts/secret-redact-pass2.py";
      description = "Path to the secret-scrubber scan script";
    };

    retentionDays = mkOption {
      type = types.int;
      default = 90;
      description = "Number of days to retain session files before cleanup";
    };

    logDir = mkOption {
      type = types.path;
      default = "/var/log/secret-hygiene";
      description = "Directory for scan reports";
    };
  };

  config = mkIf cfg.enable {
    # Ensure log directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.logDir} 0755 root root -"
    ];

    # Monthly scan service -- dry-run only, never auto-redact
    systemd.services.secret-hygiene-scan = {
      description = "Monthly dry-run scan of agent session directories for leaked secrets";
      path = with pkgs; [
        python3
        coreutils
        findutils
        gnugrep
        jq
      ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.user;
        ExecStart = pkgs.writeShellScript "secret-hygiene-scan" ''
          set -euo pipefail

          TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
          REPORT="${cfg.logDir}/scan-''${TIMESTAMP}.log"
          SUMMARY="${cfg.logDir}/scan-''${TIMESTAMP}-summary.txt"
          HITS=0

          echo "=== Secret Hygiene Scan -- $(date) ===" | tee "$REPORT"
          echo "" | tee -a "$REPORT"

          SCAN_SCRIPT="${cfg.scanScript}"

          # Session directories to scan
          SESSION_DIRS=(
            "${cfg.homeDir}/.hermes/sessions"
            "${cfg.homeDir}/.claude/transcripts"
            "${cfg.homeDir}/.omp/agent/sessions"
            "${cfg.homeDir}/.pi/agent/sessions"
          )

          for dir in "''${SESSION_DIRS[@]}"; do
            if [ ! -d "$dir" ]; then
              echo "[SKIP] $dir does not exist" | tee -a "$REPORT"
              continue
            fi

            echo "--- Scanning: $dir ---" | tee -a "$REPORT"

            if [ -x "$SCAN_SCRIPT" ]; then
              # Use the secret-scrubber with --dry-run
              if output=$("$SCAN_SCRIPT" --dry-run "$dir" 2>&1); then
                if echo "$output" | grep -qiE '(secret|key|token|password|credential|found|hit)'; then
                  echo "$output" | tee -a "$REPORT"
                  HITS=$((HITS + 1))
                else
                  echo "  No secrets detected" | tee -a "$REPORT"
                fi
              else
                echo "  [WARN] Scan script returned non-zero for $dir" | tee -a "$REPORT"
                echo "$output" | tee -a "$REPORT"
              fi
            else
              echo "  [WARN] Scan script not found at $SCAN_SCRIPT" | tee -a "$REPORT"
              echo "  Falling back to pattern-based grep scan..." | tee -a "$REPORT"

              # Fallback: grep for common secret patterns
              PATTERNS=(
                'sk-[a-zA-Z0-9]{20,}'
                'sk-ant-[a-zA-Z0-9-]{20,}'
                'ghp_[a-zA-Z0-9]{36}'
                'gho_[a-zA-Z0-9]{36}'
                'ghu_[a-zA-Z0-9]{36}'
                'ghs_[a-zA-Z0-9]{36}'
                'AKIA[0-9A-Z]{16}'
                'xox[bposa]-[0-9a-zA-Z-]{10,}'
                '[a-zA-Z0-9+/]{40}={0,2}'
              )

              DIR_HITS=0
              for pattern in "''${PATTERNS[@]}"; do
                MATCHES=$(grep -rlE "$pattern" "$dir" 2>/dev/null | head -20 || true)
                if [ -n "$MATCHES" ]; then
                  echo "  Pattern '$pattern' matched in:" | tee -a "$REPORT"
                  echo "$MATCHES" | while read -r f; do
                    echo "    $f" | tee -a "$REPORT"
                  done
                  DIR_HITS=$((DIR_HITS + 1))
                fi
              done

              if [ "$DIR_HITS" -eq 0 ]; then
                echo "  No secrets detected (fallback scan)" | tee -a "$REPORT"
              else
                HITS=$((HITS + 1))
              fi
            fi

            echo "" | tee -a "$REPORT"
          done

          # Session file counts for awareness
          echo "=== Session File Counts ===" | tee -a "$REPORT"
          for dir in "''${SESSION_DIRS[@]}"; do
            if [ -d "$dir" ]; then
              COUNT=$(find "$dir" -maxdepth 1 -type f \( -name "*.json" -o -name "*.jsonl" -o -name "session_*" -o -name "ses_*" \) | wc -l)
              OLDEST=$(find "$dir" -maxdepth 1 -type f \( -name "*.json" -o -name "*.jsonl" -o -name "session_*" -o -name "ses_*" \) -printf '%T+ %p\n' 2>/dev/null | sort | head -1 || echo "unknown")
              echo "  $dir: $COUNT files (oldest: $OLDEST)" | tee -a "$REPORT"
            fi
          done | tee -a "$REPORT"
          echo "" | tee -a "$REPORT"

          # Write summary
          if [ "$HITS" -gt 0 ]; then
            echo "RESULT: SECRETS DETECTED ($HITS directories had potential matches)" > "$SUMMARY"
            echo "Review full report at: $REPORT" >> "$SUMMARY"
          else
            echo "RESULT: CLEAN -- no secrets detected" > "$SUMMARY"
          fi

          cat "$SUMMARY" | tee -a "$REPORT"

          # Rotate old reports (keep last 12 monthly scans)
          cd "${cfg.logDir}"
          ls -t scan-*.log 2>/dev/null | tail -n +13 | xargs -r rm --
          ls -t scan-*-summary.txt 2>/dev/null | tail -n +13 | xargs -r rm --

          echo "Scan complete. Report: $REPORT"
        '';
        ProtectHome = false;
        ProtectSystem = "full";
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };

    # Monthly scan timer -- 1st of each month at 3AM
    systemd.timers.secret-hygiene-scan = {
      description = "Monthly secret hygiene scan timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-01 03:00:00";
        Persistent = true;
      };
    };

    # Weekly cleanup service -- actually deletes old session files
    systemd.services.secret-hygiene-cleanup = {
      description = "Weekly cleanup of old agent session files (older than 90 days)";
      path = with pkgs; [
        coreutils
        findutils
      ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.user;
        ExecStart = pkgs.writeShellScript "secret-hygiene-cleanup" ''
          set -euo pipefail

          RETENTION_DAYS=${toString cfg.retentionDays}
          TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
          CLEANUP_LOG="${cfg.logDir}/cleanup-''${TIMESTAMP}.log"

          echo "=== Session Cleanup -- $(date) ===" | tee "$CLEANUP_LOG"
          echo "Retention: $RETENTION_DAYS days" | tee -a "$CLEANUP_LOG"
          echo "" | tee -a "$CLEANUP_LOG"

          TOTAL_DELETED=0

          # Cleanup Hermes sessions
          HERMES_DIR="${cfg.homeDir}/.hermes/sessions"
          if [ -d "$HERMES_DIR" ]; then
            DELETED=$(find "$HERMES_DIR" -maxdepth 1 -type f \( \
              -name "session_*.json" \
              -o -name "request_dump_*.json" \
            \) -mtime +"$RETENTION_DAYS" -print -delete 2>/dev/null | wc -l || echo 0)
            echo "Hermes sessions: deleted $DELETED files" | tee -a "$CLEANUP_LOG"
            TOTAL_DELETED=$((TOTAL_DELETED + DELETED))
          fi

          # Cleanup Claude transcripts
          CLAUDE_DIR="${cfg.homeDir}/.claude/transcripts"
          if [ -d "$CLAUDE_DIR" ]; then
            DELETED=$(find "$CLAUDE_DIR" -maxdepth 1 -type f -name "ses_*.jsonl" \
              -mtime +"$RETENTION_DAYS" -print -delete 2>/dev/null | wc -l || echo 0)
            echo "Claude transcripts: deleted $DELETED files" | tee -a "$CLEANUP_LOG"
            TOTAL_DELETED=$((TOTAL_DELETED + DELETED))
          fi

          # Cleanup OMP sessions
          OMP_DIR="${cfg.homeDir}/.omp/agent/sessions"
          if [ -d "$OMP_DIR" ]; then
            DELETED=$(find "$OMP_DIR" -maxdepth 1 -type f -name "*.jsonl" \
              -mtime +"$RETENTION_DAYS" -print -delete 2>/dev/null | wc -l || echo 0)
            echo "OMP sessions: deleted $DELETED files" | tee -a "$CLEANUP_LOG"
            TOTAL_DELETED=$((TOTAL_DELETED + DELETED))
          fi

          # Cleanup Pi sessions
          PI_DIR="${cfg.homeDir}/.pi/agent/sessions"
          if [ -d "$PI_DIR" ]; then
            DELETED=$(find "$PI_DIR" -maxdepth 1 -type f -name "*.jsonl" \
              -mtime +"$RETENTION_DAYS" -print -delete 2>/dev/null | wc -l || echo 0)
            echo "Pi sessions: deleted $DELETED files" | tee -a "$CLEANUP_LOG"
            TOTAL_DELETED=$((TOTAL_DELETED + DELETED))
          fi

          echo "" | tee -a "$CLEANUP_LOG"
          echo "Total deleted: $TOTAL_DELETED files" | tee -a "$CLEANUP_LOG"

          # Rotate old cleanup logs (keep last 12)
          cd "${cfg.logDir}"
          ls -t cleanup-*.log 2>/dev/null | tail -n +13 | xargs -r rm --

          echo "Cleanup complete. Log: $CLEANUP_LOG"
        '';
        ProtectHome = false;
        ProtectSystem = "full";
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };

    # Weekly cleanup timer -- every Monday at 4AM
    systemd.timers.secret-hygiene-cleanup = {
      description = "Weekly session cleanup timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "Mon *-*-* 04:00:00";
        Persistent = true;
      };
    };
  };
}
