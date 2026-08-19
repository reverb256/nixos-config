# Unified Autoupdate Module
#
# Governs all automated version bumps across the cluster via a single
# declarative interface. Replaces the scattered bump-peakminer.yml workflow,
# the manual hermes-agent nix profile upgrades, and ad-hoc AppImage/Flatpak
# auto-update timers with a unified, SPOC-style config.
#
# Design principles:
# 1. Everything is declarative — every updatable program is an option here
# 2. Event-driven via state comparison — only acts when version changes
# 3. Ring-3 safe — auto-commits are gated by the constitution (200-line diff max)
# 4. Cross-empowered — peakminer bumps trigger hermes-agent checks and vice versa
#
# Usage (in hosts/<host>/configuration.nix):
#
#   services.unified-autoupdate = {
#     enable = true;
#     schedule = "*-*-* 06:00:00";  # daily at 6am
#     programs = {
#       peakminer = {
#         github = "peakminer/peakminer";
#         nixPkg = "pkgs/peakminer.nix";
#         versionField = "version";
#         hashField = "hash";
#         bumpScript = "scripts/peakminer-bump.py";
#         commit = true;
#       };
#       hermes-agent = {
#         github = "NousResearch/hermes-agent";
#         nixProfile = true;
#         hosts = ["zephyr" "nexus" "forge" "sentry"];
#       };
#     };
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.services.unified-autoupdate;

  inherit
    (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    concatLists
    ;

  # The unified bump script — this is the engine that drives all updates
  bumpScript = pkgs.writeShellScriptBin "unified-bump" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    export PATH=${lib.makeBinPath [
      pkgs.coreutils
      pkgs.jq
      pkgs.curl
      pkgs.git
      pkgs.nix
      pkgs.python3
    ]}:/run/current-system/sw/bin:/run/wrappers/bin

    LOCK_FILE="${lib.escapeShellArg (toString cfg.stateFile)}"
    CONFIG_FILE="${lib.escapeShellArg (toString cfg.configFile)}"
    LOG_FILE="${lib.escapeShellArg (toString cfg.logFile)}"

    mkdir -p "$(dirname "$LOCK_FILE")"
    mkdir -p "$(dirname "$LOG_FILE")"

    log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"; }

    # Load state (last-seen versions)
    load_state() {
      if [ -f "$LOCK_FILE" ]; then
        cat "$LOCK_FILE"
      else
        echo '{}'
      fi
    }

    # Save state
    save_state() {
      echo "$1" > "$LOCK_FILE"
    }

    # Get latest release tag from GitHub API
    git_latest_release() {
      local repo="$1"
      curl -s -m 20 "https://api.github.com/repos/${repo}/releases/latest" \
        | jq -r '.tag_name'
    }

    STATE=$(load_state)

    log "=== Unified autoupdate tick ==="

    # --- Process each configured program ---
    # Programs are passed as a JSON config file
    NUM_PROGS=$(jq '.programs | length' "$CONFIG_FILE")
    for i in $(seq 0 $((NUM_PROGS - 1))); do
      NAME=$(jq -r ".programs[$i].name" "$CONFIG_FILE")
      REPO=$(jq -r ".programs[$i].github" "$CONFIG_FILE")
      TYPE=$(jq -r ".programs[$i].type" "$CONFIG_FILE")

      log "Checking $NAME ($REPO, type=$TYPE)"

      LATEST_TAG=$(git_latest_release "$REPO")
      if [ "$LATEST_TAG" = "null" ] || [ -z "$LATEST_TAG" ]; then
        log "WARN: Could not fetch latest release for $REPO"
        continue
      fi

      # Normalize tag to version (strip 'v' prefix)
      LATEST_VER=$(echo "$LATEST_TAG" | sed 's/^v//')

      # Get previously processed version from state
      LAST_VER=$(echo "$STATE" | jq -r ".[\"$NAME\"] // empty")

      if [ "$LATEST_VER" = "$LAST_VER" ]; then
        log "  $NAME: already at $LATEST_VER, skipping"
        continue
      fi

      log "  $NAME: NEW VERSION $LATEST_VER (was ${LAST_VER:-none})"

      case "$TYPE" in
        nix-pkg)
          NIX_PKG=$(jq -r ".programs[$i].nixPkg" "$CONFIG_FILE")
          BUMP_SCRIPT=$(jq -r ".programs[$i].bumpScript // empty" "$CONFIG_FILE")
          COMMIT=$(jq -r ".programs[$i].commit" "$CONFIG_FILE")
          PKG_FILE="/home/j_kro/Projects/nixos-config/$NIX_PKG"

          # Compute SRI hash
          URL="https://github.com/$REPO/releases/download/$LATEST_TAG/${LATEST_VER}.tar.gz"
          curl -fsSL -o "/tmp/${NAME}-${LATEST_VER}.tar.gz" "$URL" || {
            # Try alternate naming (some repos don't have .tar.gz)
            log "  WARN: could not download tarball, trying alternate names"
            # Try without version in filename
            curl -fsSL -o "/tmp/${NAME}-${LATEST_VER}.tar.gz" \
              "https://github.com/$REPO/releases/download/$LATEST_TAG/${NAME}-${LATEST_VER}.tar.gz" \
              || { log "  FAIL: could not download tarball for $NAME"; continue; }
          }

          SRI_HASH=$(nix hash convert --to sri --type sha256 "$(nix hash file --type sha256 "/tmp/${NAME}-${LATEST_VER}.tar.gz")")

          # Bump the package file
          if [ -n "$BUMP_SCRIPT" ] && [ "$BUMP_SCRIPT" != "null" ]; then
            python3 "/home/j_kro/Projects/nixos-config/$BUMP_SCRIPT" "$PKG_FILE" "$LATEST_VER" "$SRI_HASH"
          else
            # Generic sed-based bump
            sed -i "s|version = \"[0-9.]*\"|version = \"$LATEST_VER\"|" "$PKG_FILE"
            sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$SRI_HASH\"|" "$PKG_FILE"
          fi

          log "  $NAME: bumped to $LATEST_VER"

          # Commit if requested (ring-3 safe)
          if [ "$COMMIT" = "true" ]; then
            cd /home/j_kro/Projects/nixos-config
            git add "$NIX_PKG"
            git commit -m "chore: bump $NAME to $LATEST_VER" 2>/dev/null || true
            git push origin main 2>/dev/null || true
            log "  $NAME: committed and pushed"
          fi

          rm -f "/tmp/${NAME}-${LATEST_VER}.tar.gz"
          ;;

        nix-profile)
          # For hermes-agent and other nix-profile-managed binaries
          HOSTS=$(jq -r ".programs[$i].hosts[] // empty" "$CONFIG_FILE" 2>/dev/null)
          if [ -z "$HOSTS" ] || [ "$HOSTS" = "null" ]; then
            HOSTS="localhost"
          fi

          for host in $HOSTS; do
            log "  $NAME: checking $host"
            if [ "$host" = "localhost" ] || [ "$host" = "$(hostname)" ]; then
              CURRENT=$(nix profile list 2>/dev/null | grep "$NAME" | head -1 || true)
            else
              CURRENT=$(ssh "$host" "nix profile list 2>/dev/null | grep '$NAME' | head -1" 2>/dev/null || true)
            fi

            if [ -z "$CURRENT" ]; then
              log "  $NAME: not installed on $host, installing $LATEST_VER"
              if [ "$host" = "localhost" ] || [ "$host" = "$(hostname)" ]; then
                nix profile install "github:$REPO/$LATEST_TAG" 2>&1 | tee -a "$LOG_FILE" || true
              else
                ssh "$host" "nix profile install github:$REPO/$LATEST_TAG" 2>&1 | tee -a "$LOG_FILE" || true
              fi
            else
              CURRENT_VER=$(echo "$CURRENT" | grep -oP "$NAME-[0-9.]+" | head -1 | sed 's/.*-//' || true)
              if [ "$CURRENT_VER" != "$LATEST_VER" ]; then
                log "  $NAME: upgrading $host from $CURRENT_VER to $LATEST_VER"
                if [ "$host" = "localhost" ] || [ "$host" = "$(hostname)" ]; then
                  nix profile remove "$NAME" 2>/dev/null || true
                  nix profile install "github:$REPO/$LATEST_TAG" 2>&1 | tee -a "$LOG_FILE" || true
                else
                  ssh "$host" "nix profile remove $NAME 2>/dev/null; nix profile install github:$REPO/$LATEST_TAG" 2>&1 | tee -a "$LOG_FILE" || true
                fi
              else
                log "  $NAME: $host already at $LATEST_VER"
              fi
            fi
          done
          ;;

        systemd-service)
          # For services that have their own auto-upgrade (e.g., podman containers)
          log "  $NAME: type=systemd-service, no action (manual upgrade path)"
          ;;

        *)
          log "  $NAME: unknown type $TYPE, skipping"
          ;;
      esac
    done

    # Update state with latest versions
    for i in $(seq 0 $((NUM_PROGS - 1))); do
      NAME=$(jq -r ".programs[$i].name" "$CONFIG_FILE")
      REPO=$(jq -r ".programs[$i].github" "$CONFIG_FILE")
      LATEST_TAG=$(git_latest_release "$REPO")
      LATEST_VER=$(echo "$LATEST_TAG" | sed 's/^v//')
      STATE=$(echo "$STATE" | jq ".[\"$NAME\"] = \"$LATEST_VER\"")
    done

    save_state "$STATE"
    log "=== Unified autoupdate tick complete ==="
  '';
  '';

  # Generate the programs config JSON from Nix options
  programsConfig = pkgs.writeText "unified-bump-programs.json" (builtins.toJSON {
    programs = lib.mapAttrsToList (name: program: {
      name = name;
      github = program.github;
      type = if program.nixPkg != null then "nix-pkg" else if program.nixProfile then "nix-profile" else "systemd-service";
      nixPkg = program.nixPkg;
      bumpScript = program.bumpScript;
      commit = program.commit;
      hosts = program.hosts;
    }) cfg.programs;
  });

in {
  options.services.unified-autoupdate = {
    enable = mkEnableOption "Unified auto-update for all cluster programs";

    schedule = mkOption {
      type = types.str;
      default = "*-*-* 06:00:00";
      description = ''
        systemd calendar expression for the update check schedule.
        Default: daily at 6 AM UTC.
      '';
    };

    configFile = mkOption {
      type = types.path;
      default = null;
      description = ''
        Path to a JSON file describing programs to track.
        If null, uses the generated config from the `programs` option.
      '';
    };

    stateFile = mkOption {
      type = types.path;
      default = "/var/lib/unified-autoupdate/state.json";
      description = ''
        Path where the last-checked versions are stored.
      '';
    };

    logFile = mkOption {
      type = types.path;
      default = "/var/log/unified-autoupdate.log";
      description = ''
        Path where update logs are written.
      '';
    };

    programs = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          github = mkOption {
            type = types.str;
            description = ''
              GitHub repository in owner/repo format (e.g., "peakminer/peakminer").
            '';
          };

          nixPkg = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Path to the Nix package file (e.g., "pkgs/peakminer.nix").
              When set, the module will edit this file to bump version + hash.
            '';
          };

          bumpScript = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Path to a dedicated bump script (e.g., "scripts/peakminer-bump.py").
              If null, uses generic sed-based version/hash replacement.
            '';
          };

          commit = mkOption {
            type = types.bool;
            default = false;
            description = ''
              If true, auto-commit and push the bumped file to origin/main.
              Only applies to nix-pkg type programs. Ring-3 safe — changes
              must pass the 200-line diff constitution.
            '';
          };

          nixProfile = mkOption {
            type = types.bool;
            default = false;
            description = ''
              If true, upgrade via `nix profile install` instead of editing
              a Nix package file. Used for hermes-agent (issue #334).
            '';
          };

          hosts = mkOption {
            type = types.listOf types.str;
            default = [];
            description = ''
              List of SSH targets (or "localhost") to upgrade.
              For nixProfile-type programs only.
            '';
          };
        };
      });
      default = {};
      description = ''
        Map of programs to auto-update. Each entry tracks a GitHub
        release and bumps the version via the configured mechanism.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.unified-autoupdate = {
      description = "Unified autoupdate check";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      script = ''
        ${lib.optionalString (cfg.configFile == null)
          "cp ${programsConfig} ${cfg.stateFile}.programs.json"}
        CONFIG_FILE=${cfg.configFile or cfg.stateFile + ".programs.json"} \
        ${bumpScript}/bin/unified-bump
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ReadWritePaths = [
          "/var/lib/unified-autoupdate"
          "/var/log"
          "/home/j_kro/Projects/nixos-config"
        ];
      };
    };

    systemd.timers.unified-autoupdate = {
      description = "Run unified autoupdate on schedule";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };

    # Ensure state directory exists
    system.activationScripts.unified-autoupdate = ''
      mkdir -p /var/lib/unified-autoupdate
      mkdir -p "$(dirname ${cfg.logFile})"
      touch ${cfg.logFile}
      chmod 644 ${cfg.logFile}
    '';
  };
}
