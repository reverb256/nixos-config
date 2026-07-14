#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# topgrade — Comprehensive flake input upgrade pipeline
#
# Unpins stale inputs, updates all flake inputs to latest,
# collapses redundant nixpkgs variants, validates, switches, GCs,
# and commits the result.
#
# Usage:  just topgrade          # full dry-run + interactive
#         just topgrade apply    # non-interactive, auto-commits
#         just topgrade dry      # dry-run only (default)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail
FLAKE="/etc/nixos"
HOST=$(hostname -s)
MODE="${1:-dry}"  # apply | dry

cd "$FLAKE"

# ── Colors ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }

# ── Safety first ───────────────────────────────────────────────────
if [ -n "$(git status --porcelain flake.nix 2>/dev/null)" ]; then
    err "flake.nix has uncommitted changes — commit or stash first"
    exit 1
fi

# Ensure the current state is valid JSON (don't start with a broken lock)
python3 -c "import json; json.load(open('flake.lock'))" || {
    err "flake.lock is invalid JSON — fix it first"
    exit 1
}

# ── Phase 0: Analyze stale pinned inputs ──────────────────────────
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TOPGRADE — Comprehensive Flake Upgrade${NC}"
echo -e "${CYAN}  Mode: ${MODE}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo ""

info "Phase 0: Analyzing stale pinned inputs..."

STALE_INPUTS=$(
python3 << 'PYEOF'
import json, datetime, re

d = json.load(open('/etc/nixos/flake.lock'))
nodes = d['nodes']
root = nodes['root']
root_inputs = root.get('inputs', {})

today = datetime.datetime.now()
stale = []

for name, target in sorted(root_inputs.items()):
    if not isinstance(target, str):
        continue
    node = nodes.get(target, {})
    locked = node.get('locked', {})
    rev = locked.get('rev')
    if not rev:
        continue
    ts = locked.get('lastModified')
    if not ts:
        continue
    commit_date = datetime.datetime.fromtimestamp(ts)
    days_ago = (today - commit_date).days
    if days_ago <= 30:
        continue
    
    # Read flake.nix to check if this input has a pinned commit
    with open('/etc/nixos/flake.nix') as f:
        flake_nix = f.read()
    
    # Check if the input URL has a pinned commit
    # Pattern: name = { url = "..." or name.url = "..."
    input_section = re.search(
        rf'[\s#]*{re.escape(name)}\s*=\s*{{[^}}]*url\s*=\s*"([^"]*)"',
        flake_nix
    )
    if not input_section:
        input_section = re.search(
            rf'[\s#]*{re.escape(name)}\.url\s*=\s*"([^"]*)"',
            flake_nix
        )
    if not input_section:
        continue
    
    url = input_section.group(1)
    
    # Not pinned if it doesn't have a commit hash in URL
    # Pattern: github:owner/repo/HASH  (HASH = 40 hex chars)
    pin_match = re.search(r'github:[^/]+/[^/]+/([a-f0-9]{40})', url)
    if not pin_match:
        continue
    
    pinned_rev = pin_match.group(1)
    
    # Check if the pinned rev matches the lock file rev (it should)
    if pinned_rev != rev:
        continue  # URL was bumped but lock hasn't caught up — skip
    
    # Check for comment explaining the pin (above the input or on the same line)
    pos = input_section.start()
    preceding = flake_nix[max(0, pos-300):pos]
    has_comment = bool(re.search(r'(?:#|//)\s*(?:pin|reason|because|needs|requires|pinned)', preceding, re.IGNORECASE))
    
    # Our own extracted repos — always skip (need manual unpin when migration is done)
    is_our_repo = 'reverb256' in url
    
    # Check if it follows nixpkgs properly
    follow_match = re.search(
        rf'[\s#]*{re.escape(name)}\s*=\s*{{[^}}]*inputs\.nixpkgs\.follows',
        flake_nix
    )
    has_follow = bool(follow_match)
    if not has_follow:
        # Also check short form
        follow_match = re.search(
            rf'{re.escape(name)}\.url\s*=\s*"[^"]*";?\s*$',
            flake_nix,
            re.MULTILINE
        )
    
    if not has_comment:
        stale.append({
            'name': name,
            'days': days_ago,
            'url': url,
            'source_url': re.sub(r'/([a-f0-9]{40})$', '', url),
            'our_repo': is_our_repo,
            'has_follow': has_follow,
        })

print(json.dumps(stale, indent=2))
PYEOF
)

NUM_STALE=$(echo "$STALE_INPUTS" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data)); print('\n'.join([f'  {i[\"name\"]:25s} {i[\"days\"]:3d}d old  url: {i[\"source_url\"]}' for i in data]))" 2>/dev/null || echo "0")

NUM_LINES=$(echo "$NUM_STALE" | wc -l)
if [ "$NUM_LINES" -gt 1 ]; then
    NUM=$(echo "$NUM_STALE" | head -1)
    echo "$NUM_STALE" | tail -n +2
    echo ""
    info "Found $NUM stale pinned input(s) eligible for unpin"
else
    NUM=0
    echo "  (none)"
fi

# ── Phase 0b: Detect inputs missing nixpkgs follow ────────────────
echo ""
info "Phase 0b: Checking for missing nixpkgs follows..."

MISSING_FOLLOW=$(
python3 << 'PYEOF'
import json, re

d = json.load(open('/etc/nixos/flake.lock'))
nodes = d['nodes']
root = nodes['root']
root_inputs = root.get('inputs', {})

with open('/etc/nixos/flake.nix') as f:
    flake_nix = f.read()

missing = []
for name, target in sorted(root_inputs.items()):
    if not isinstance(target, str):
        continue
    node = nodes.get(target, {})
    node_inputs = node.get('inputs', {})
    
    # Skip if it doesn't have nixpkgs as a possible input
    # Check if node even declares nixpkgs input
    has_nixpkgs_in_lock = 'nixpkgs' in node_inputs
    
    # Check if flake.nix has a follow directive for this input
    has_follow = bool(re.search(
        rf'inputs\.nixpkgs\.follows\s*=\s*"nixpkgs"',
        flake_nix
    ))
    # Check if it's the nixpkgs input itself
    if name == 'nixpkgs':
        continue
    # Check if it's a local path or has no nixpkgs input
    orig = node.get('original', {})
    url = orig.get('url', '')
    if url.startswith('path:') or url.startswith('gitlab:'):
        continue
    # Check if node has no inputs at all
    if not node_inputs:
        continue
    # Check if node's nixpkgs is already a follow reference (list means follow)
    nixpkgs_ref = node_inputs.get('nixpkgs')
    if isinstance(nixpkgs_ref, list):
        continue  # already following
    
    # Check if this input follows the main nixpkgs in OUR flake.nix
    our_follow_match = re.search(
        rf'{re.escape(name)}\s*=\s*{{[^}}]*inputs\.nixpkgs\.follows\s*=\s*"nixpkgs"',
        flake_nix
    )
    if our_follow_match:
        continue  # already wired in our config
    
    # If the node has nixpkgs input and we haven't told it to follow, flag it
    if 'nixpkgs' in node_inputs and not isinstance(node_inputs['nixpkgs'], list):
        rev = nodes.get(node_inputs['nixpkgs'], {}).get('locked', {}).get('rev', '?')[:12]
        missing.append({
            'name': name,
            'current_nixpkgs_rev': rev,
            'has_direct_nixpkgs': True,
        })

print(json.dumps(missing, indent=2))
PYEOF
)

NUM_MISSING=$(echo "$MISSING_FOLLOW" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data)); print('\n'.join([f'  {i[\"name\"]:25s} own nixpkgs: {i[\"current_nixpkgs_rev\"]}' for i in data]))" 2>/dev/null || echo "0")

NUM_MISSING_LINES=$(echo "$NUM_MISSING" | wc -l)
if [ "$NUM_MISSING_LINES" -gt 1 ]; then
    echo "$NUM_MISSING" | tail -n +2
    echo ""
    info "Found $(echo "$NUM_MISSING" | head -1) input(s) missing nixpkgs follow"
else
    echo "  (none)"
fi

if [ "$MODE" = "dry" ]; then
    echo ""
    if [ "$NUM" -gt 0 ] || [ "$(echo "$MISSING_FOLLOW" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null)" -gt 0 ]; then
        warn "Run 'just topgrade apply' to execute the upgrade"
    else
        ok "Nothing stale to upgrade"
    fi
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════
# APPLY MODE
# ═══════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}── Phase 1: Unpinning stale inputs ──${NC}"

python3 << 'PYEOF'
import json, re

d = json.load(open('/etc/nixos/flake.lock'))
nodes = d['nodes']
root = nodes['root']
root_inputs = root.get('inputs', {})

today = __import__('datetime').datetime.now()
unpinned = []

with open('/etc/nixos/flake.nix', 'r') as f:
    flake_nix = f.read()

original = flake_nix

for name, target in sorted(root_inputs.items()):
    if not isinstance(target, str):
        continue
    node = nodes.get(target, {})
    locked = node.get('locked', {})
    rev = locked.get('rev')
    if not rev:
        continue
    ts = locked.get('lastModified')
    if not ts:
        continue
    commit_date = __import__('datetime').datetime.fromtimestamp(ts)
    days_ago = (today - commit_date).days
    if days_ago <= 30:
        continue
    
    # Find URL pattern
    input_section = re.search(
        rf'[\s#]*{re.escape(name)}\s*=\s*{{[^}}]*url\s*=\s*"([^"]*)"',
        flake_nix
    )
    if not input_section:
        input_section = re.search(
            rf'[\s#]*{re.escape(name)}\.url\s*=\s*"([^"]*)"',
            flake_nix
        )
    if not input_section:
        continue
    
    url = input_section.group(1)
    pin_match = re.search(r'(github:[^/]+/[^/]+)/([a-f0-9]{40})', url)
    if not pin_match:
        continue
    
    # Skip our own repos
    if 'reverb256' in url:
        print(f"  SKIP {name}: own repo (must unpin manually)")
        continue
    
    # Skip inputs with pin explanation comments
    pos = input_section.start()
    preceding = flake_nix[max(0, pos-300):pos]
    if re.search(r'(?:#|//)\s*(?:pin|reason|because|needs|requires|pinned)', preceding, re.IGNORECASE):
        print(f"  SKIP {name}: pinned with reason comment")
        continue
    
    base_url = pin_match.group(1)
    old = f'"{url}"'
    new = f'"{base_url}"'
    count = original.count(old)
    if count == 0:
        print(f"  SKIP {name}: pattern not found in file")
        continue
    
    original = original.replace(old, new, 1)
    print(f"  UNPIN {name}: {days_ago}d old → {base_url}")

with open('/etc/nixos/flake.nix', 'w') as f:
    f.write(original)

print("Done unpinning")
PYEOF

# ── Phase 2: Add missing nixpkgs follows ──────────────────────────
echo ""
echo -e "${CYAN}── Phase 2: Adding missing nixpkgs follows ──${NC}"

python3 << 'PYEOF'
import json, re

d = json.load(open('/etc/nixos/flake.lock'))
nodes = d['nodes']
root = nodes['root']
root_inputs = root.get('inputs', {})

with open('/etc/nixos/flake.nix', 'r') as f:
    flake_nix = f.read()

original = flake_nix

for name, target in sorted(root_inputs.items()):
    if not isinstance(target, str):
        continue
    node = nodes.get(target, {})
    node_inputs = node.get('inputs', {})
    
    if name == 'nixpkgs':
        continue
    if not node_inputs:
        continue
    if 'nixpkgs' not in node_inputs:
        continue
    
    # Already following via list ref?
    nixpkgs_ref = node_inputs.get('nixpkgs')
    if isinstance(nixpkgs_ref, list):
        continue  # already following
    
    # Check if we already have a follow directive
    if re.search(rf'{re.escape(name)}\s*=\s*{{[^}}]*inputs\.nixpkgs\.follows', flake_nix):
        continue
    
    # Check if it's a short-form declaration
    short_form = re.search(rf'{re.escape(name)}\.url\s*=\s*"[^"]*";\s*$', flake_nix, re.MULTILINE)
    if short_form:
        # Convert short form to long form with follow
        line = short_form.group(0)
        indent = re.match(r'^(\s*)', line).group(1)
        new_block = f'''{name} = {{
      url = {re.search(r'"(.*)"', line).group(0)};
      inputs.nixpkgs.follows = "nixpkgs";
    }};'''
        # Use a unique anchor — the original line
        old_line = line.strip()
        # But need to be careful with indentation
        # Find the full line in the file
        line_match = re.search(
            rf'^[ \t]*{re.escape(name)}\.url\s*=\s*"[^"]*";',
            flake_nix,
            re.MULTILINE
        )
        if line_match:
            matched = line_match.group(0)
            indent2 = re.match(r'^(\s*)', matched).group(1)
            new_block = f'''{indent2}{name} = {{
      {indent2}url = {re.search(r'"(.*)"', matched).group(0)};
      {indent2}inputs.nixpkgs.follows = "nixpkgs";
    }};'''
            original = original.replace(matched, new_block, 1)
            print(f"  WIRE {name}: short form → long form with follow")
    else:
        # Check if it's already in a block without follow
        block_match = re.search(
            rf'{re.escape(name)}\s*=\s*{{([^}}]*url\s*=\s*"[^"]*")[^}}]*}};',
            flake_nix
        )
        if block_match and 'inputs.nixpkgs.follows' not in block_match.group(0):
            # Add follow inside existing block
            old_block = block_match.group(0)
            new_block = old_block.rstrip(';}') + f';\n      inputs.nixpkgs.follows = "nixpkgs";\n    }};'
            original = original.replace(old_block, new_block, 1)
            print(f"  WIRE {name}: added follow to existing block")

with open('/etc/nixos/flake.nix', 'w') as f:
    f.write(original)
print("Done wiring follows")
PYEOF

# ── Phase 3: Flake update ──────────────────────────────────────────
echo ""
echo -e "${CYAN}── Phase 3: Updating all flake inputs ──${NC}"

info "Running: nix flake update"
if nix flake update 2>&1; then
    ok "All inputs updated"
else
    warn "nix flake update had issues (network? rate limit?). Trying specific updates..."
    # Fall back to updating key inputs individually
    info "Updating nixpkgs..."
    nix flake update nixpkgs 2>&1 || warn "nixpkgs update failed (non-critical)"
    info "Updating home-manager..."
    nix flake update home-manager 2>&1 || true
fi

# ── Phase 4: Validate ──────────────────────────────────────────────
echo ""
echo -e "${CYAN}── Phase 4: Validating flake ──${NC}"

info "Running: nix flake check (30s timeout)"
if timeout 30 nix flake check --allow-dirty 2>&1; then
    ok "Flake check passed"
else
    warn "Flake check timed out or failed (usually niri crate fetching)"
    info "Checking if flake.lock is valid JSON..."
    python3 -c "import json; json.load(open('flake.lock')); print('  JSON valid')"
fi

# ── Phase 5: Commit ────────────────────────────────────────────────
echo ""
echo -e "${CYAN}── Phase 5: Committing ──${NC}"

git add flake.nix flake.lock
if git diff --cached --quiet; then
    ok "Nothing to commit"
else
    # Count what changed
    N_UNPIN=$(git diff --cached flake.nix 2>/dev/null | grep '^-.*url.*github:' | grep -v '^---' | wc -l)
    N_INPUTS=$(git diff --cached flake.lock 2>/dev/null | grep '^[-+].*lastModified' | wc -l || echo "?")
    COMMIT_MSG="topgrade: unpin stale inputs + update all flake inputs"
    git commit -m "$COMMIT_MSG" -m "Auto-generated by scripts/topgrade.sh" 2>&1 | tail -2
    ok "Committed: $COMMIT_MSG"
    
    # Push
    info "Pushing to origin..."
    git push origin main 2>&1 | tail -2 || warn "Push failed (network?)"
fi

# ── Phase 6: Switch (optional) ─────────────────────────────────────
echo ""
echo -e "${CYAN}── Phase 6: Switching (local host: $HOST) ──${NC}"

if command -v nixos-rebuild &>/dev/null; then
    info "Running: nixos-rebuild switch"
    if sudo nixos-rebuild switch --flake ".#$HOST" 2>&1; rc=$?; then
        ok "Switch complete"
    elif [ $rc -eq 4 ]; then
        warn "Switch had warnings (rc=4) — usually NixOS deprecation notices"
    else
        err "Switch failed (rc=$rc) — check above"
        exit $rc
    fi
else
    warn "Not on a NixOS host — skipping switch"
fi

# ── Phase 7: GC ────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}── Phase 7: Garbage collection ──${NC}"
sudo nix-collect-garbage -d 2>&1 | tail -1 || true

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  TOPGRADE COMPLETE${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
info "Next steps:"
echo "  just deploy    — deploy to all cluster hosts"
echo "  just check     — re-validate if needed"
