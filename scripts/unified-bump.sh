#!/bin/bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/run/wrappers/bin:${PATH:-}"

LOCK_FILE="${1:-/var/lib/unified-autoupdate/state.json}"
CONFIG_FILE="${2:-/var/lib/unified-autoupdate/programs.json}"
LOG_FILE="${3:-/var/log/unified-autoupdate.log}"

mkdir -p "$(dirname "$LOCK_FILE")"
mkdir -p "$(dirname "$LOG_FILE")"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"; }

load_state() {
  if [ -f "$LOCK_FILE" ]; then
    cat "$LOCK_FILE"
  else
    echo "{}"
  fi
}

save_state() {
  echo "$1" > "$LOCK_FILE"
}

git_latest_release() {
  local repo="$1"
  curl -s -m 20 "https://api.github.com/repos/${repo}/releases/latest" \
    | jq -r ".tag_name"
}

STATE=$(load_state)
log "=== Unified autoupdate tick ==="

NUM_PROGS=$(jq ".programs | length" "$CONFIG_FILE")
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

  LATEST_VER=$(echo "$LATEST_TAG" | sed "s/^v//")
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

      URL="https://github.com/$REPO/releases/download/$LATEST_TAG/${LATEST_VER}.tar.gz"
      DL_FILE="/tmp/${NAME}-${LATEST_VER}.tar.gz"

      curl -fsSL -o "$DL_FILE" "$URL" || {
        log "  WARN: could not download tarball, trying alternate name"
        ALT_URL="https://github.com/$REPO/releases/download/$LATEST_TAG/${NAME}-${LATEST_VER}.tar.gz"
        curl -fsSL -o "$DL_FILE" "$ALT_URL" || {
          log "  FAIL: could not download tarball for $NAME"
          continue
        }
      }

      SRI_HASH=$(nix hash convert --to sri --type sha256 "$(nix hash file --type sha256 "$DL_FILE")")

      if [ -n "$BUMP_SCRIPT" ] && [ "$BUMP_SCRIPT" != "null" ]; then
        python3 "/home/j_kro/Projects/nixos-config/$BUMP_SCRIPT" "$PKG_FILE" "$LATEST_VER" "$SRI_HASH"
      else
        sed -i "s|version = \"[0-9.]*\"|version = \"$LATEST_VER\"|" "$PKG_FILE"
        sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$SRI_HASH\"|" "$PKG_FILE"
      fi

      log "  $NAME: bumped to $LATEST_VER"

      if [ "$COMMIT" = "true" ]; then
        cd /home/j_kro/Projects/nixos-config
        git add "$NIX_PKG"
        git commit -m "chore: bump $NAME to $LATEST_VER" 2>/dev/null || true
        git push origin main 2>/dev/null || true
        log "  $NAME: committed and pushed"
      fi

      rm -f "$DL_FILE"
      ;;

    nix-profile)
      HOSTS=$(jq -r ".programs[$i].hosts[]?" "$CONFIG_FILE" 2>/dev/null)
      if [ -z "$HOSTS" ] || [ "$HOSTS" = "null" ]; then
        HOSTS=$(hostname)
      fi

      for host in $HOSTS; do
        log "  $NAME: checking $host"
        if [ "$host" = "$(hostname)" ] || [ "$host" = "localhost" ]; then
          CURRENT=$(nix profile list 2>/dev/null | grep "$NAME" | head -1 || true)
        else
          CURRENT=$(ssh "$host" "nix profile list 2>/dev/null | grep '$NAME' | head -1" 2>/dev/null || true)
        fi

        if [ -z "$CURRENT" ]; then
          log "  $NAME: not installed on $host, installing $LATEST_TAG"
          if [ "$host" = "$(hostname)" ] || [ "$host" = "localhost" ]; then
            nix profile install "github:$REPO/$LATEST_TAG" 2>&1 | tee -a "$LOG_FILE" || true
          else
            ssh "$host" "nix profile install github:$REPO/$LATEST_TAG" 2>&1 | tee -a "$LOG_FILE" || true
          fi
        else
          CURRENT_TAG=$(echo "$CURRENT" | grep -oP "$NAME-[0-9.]+" | head -1 | sed "s/.*-//" || true)
          if [ "$CURRENT_TAG" != "$LATEST_VER" ]; then
            log "  $NAME: upgrading $host from $CURRENT_TAG to $LATEST_VER"
            if [ "$host" = "$(hostname)" ] || [ "$host" = "localhost" ]; then
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
      log "  $NAME: type=systemd-service, no auto action"
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
  LATEST_VER=$(echo "$LATEST_TAG" | sed "s/^v//")
  STATE=$(echo "$STATE" | jq ".[\"$NAME\"] = \"$LATEST_VER\"")
done

save_state "$STATE"
log "=== Unified autoupdate tick complete ==="
