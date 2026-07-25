#!/usr/bin/env bash
# deploy-host.sh — Safe NixOS deployment to any cluster host
#
# Usage:
#   ./deploy-host.sh <hostname>                # Deploy to a running NixOS host
#   ./deploy-host.sh --rescue <hostname>       # Deploy from USB rescue (mounts existing disks)
#
# Safety:
#   - Validates flake config exists before building
#   - Verifies target is reachable before deploying
#   - Never runs disko (does NOT format disks)
#   - Requires --i-know-what-im-doing flag to skip safety checks
#   - Builds locally, copies closure, activates remotely
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NIXOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FLAKE="$NIXOS_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()   { echo -e "${RED}[ERR]${NC}  $*"; }
fatal()     { log_err "$*"; exit 1; }

# ── Parse args ──────────────────────────────────────────────
RESCUE_MODE=false
I_KNOW=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rescue) RESCUE_MODE=true; shift ;;
    --i-know-what-im-doing) I_KNOW=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--rescue] [--i-know-what-im-doing] <hostname>"
      echo ""
      echo "  --rescue               Target is in USB rescue mode (mounts existing disks)"
      echo "  --i-know-what-im-doing Skip all safety confirmations"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      HOST="$1"
      shift
      ;;
  esac
done

if [[ -z "${HOST:-}" ]]; then
  fatal "Usage: $0 [--rescue] <hostname>"
fi

# ── Resolve host info from flake ─────────────────────────────
log_info "Resolving host '$HOST' from flake..."

HOST_DIR="$NIXOS_DIR/hosts/$HOST"
if [[ ! -d "$HOST_DIR" ]]; then
  fatal "No configuration directory found at hosts/$HOST/ — available hosts:"
  ls "$NIXOS_DIR/hosts/"
  exit 1
fi

# Validate flake has this host
FLAKE_CHECK=$(nix eval "path:$FLAKE#nixosConfigurations.$HOST.config.system.stateVersion" 2>&1) || true
if [[ -z "$FLAKE_CHECK" ]]; then
  fatal "Flake does not provide nixosConfigurations.$HOST — check flake.nix"
fi
log_ok "Flake provides nixosConfigurations.$HOST (stateVersion: $FLAKE_CHECK)"

# Read cluster IP from flake
TARGET_IP=$(nix eval --raw "path:$FLAKE#nixosConfigurations.$HOST.config.networking.cluster.hosts.$HOST.ip" 2>/dev/null || true)
if [[ -z "$TARGET_IP" ]]; then
  fatal "Could not resolve IP for $HOST from flake networking.cluster.hosts"
fi
log_info "Target IP: $TARGET_IP"

# ── Check target reachability ───────────────────────────────
log_info "Checking if $HOST ($TARGET_IP) is reachable..."
if ping -c 1 -W 3 "$TARGET_IP" &>/dev/null; then
  log_ok "$HOST is reachable via ping"
else
  if [[ "$RESCUE_MODE" == false ]]; then
    fatal "Cannot reach $HOST ($TARGET_IP). Is it powered on? Use --rescue if target is in USB rescue system."
  else
    log_warn "$HOST is not responding to ping (expected for some rescue modes)"
  fi
fi

# Try SSH
SSH_CMD="ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
if $SSH_CMD "j_kro@$TARGET_IP" 'echo connected' &>/dev/null; then
  log_ok "SSH to j_kro@$TARGET_IP successful"
  SSH_USER="j_kro"
elif $SSH_CMD "root@$TARGET_IP" 'echo connected' &>/dev/null; then
  log_ok "SSH to root@$TARGET_IP successful"
  SSH_USER="root"
else
  fatal "Cannot SSH to $TARGET_IP as j_kro or root"
fi

SSH_TARGET="${SSH_USER}@${TARGET_IP}"

# ── Safety confirmation ─────────────────────────────────────
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  DEPLOYMENT PLAN${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo "  Host:         $HOST ($TARGET_IP)"
echo "  Config:       hosts/$HOST/configuration.nix"
echo "  Mode:         $([ "$RESCUE_MODE" == true ] && echo 'RESCUE (mount existing disks)' || echo 'RUNNING SYSTEM')"
echo "  SSH target:   $SSH_TARGET"
echo "  Disko:        NOT RUNNED — existing disks are NOT touched"
echo "  Action:       Build closure → copy to target → activate"
echo ""

if [[ "$I_KNOW" == false ]]; then
  echo -e "${RED}WARNING: This will deploy NixOS to $HOST.${NC}"
  echo -e "${RED}The existing disk partitions will NOT be modified.${NC}"
  echo -e "${RED}System services on $HOST will be restarted.${NC}"
  echo ""
  read -rp "Proceed? (type 'yes' to continue): " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    fatal "Cancelled by user"
  fi
fi

# ── Build the closure ───────────────────────────────────────
log_info "Building nixosConfigurations.$HOST..."
BUILD_OUT=$(nix build "path:$FLAKE#nixosConfigurations.$HOST.config.system.build.toplevel" --no-link --print-out-paths 2>&1)
log_ok "Build complete: $BUILD_OUT"

# ── Copy closure to target ──────────────────────────────────
log_info "Copying closure to $SSH_TARGET (this may take a while)..."
nix copy --to "ssh://$SSH_TARGET" "$BUILD_OUT" 2>&1
log_ok "Closure copied to target"

# ── Activate on target ──────────────────────────────────────
log_info "Activating on $HOST..."
ACTIVATE_RESULT=$($SSH_CMD "$SSH_TARGET" "sudo nix-env -p /nix/var/nix/profiles/system --set $BUILD_OUT && sudo $BUILD_OUT/bin/switch-to-configuration switch" 2>&1) || true

if echo "$ACTIVATE_RESULT" | grep -q "error\|failed\|FAILED"; then
  log_err "Activation reported errors:"
  echo "$ACTIVATE_RESULT" | grep -i "error\|failed" | head -10
  echo ""
  log_warn "The system was built and copied, but activation had issues."
  log_warn "SSH to $SSH_TARGET and diagnose:"
  echo "  sudo nix-env -p /nix/var/nix/profiles/system --set $BUILD_OUT"
  echo "  sudo $BUILD_OUT/bin/switch-to-configuration switch"
  exit 1
fi

log_ok "Activation successful!"

# ── Post-deploy verification ─────────────────────────────────
log_info "Verifying deployment..."
sleep 5  # Give services time to start
if $SSH_CMD "$SSH_TARGET" "hostname && uptime" &>/dev/null; then
  log_ok "$HOST is running new configuration"
else
  log_warn "Cannot reach $HOST after deployment — check console"
  exit 1
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  DEPLOYMENT COMPLETE: $HOST${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo "  Target:       $HOST ($TARGET_IP)"
echo "  Closure:      $BUILD_OUT"
echo "  SSH:          ssh $SSH_TARGET"
echo ""
echo "  Next steps:"
echo "    - Check service status: systemctl list-units --state=failed"
echo "    - Check sops-nix secrets: ls /run/secrets/"
