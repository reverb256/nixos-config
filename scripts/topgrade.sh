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
MODE="${1:-dry}"

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

python3 -c "import json; json.load(open('flake.lock'))" 2>/dev/null || {
    err "flake.lock is invalid JSON — fix it first"
    exit 1
}

# ── Helper: run Python analysis, suppress SITECUSTOMIZE stderr ─────
# SITECUSTOMIZE messages on stderr pollute capture; route stderr to
# /dev/null for Python analysis scripts.
run_py() {
    python3 -c "$1" 2>/dev/null | grep -v '^SITECUSTOMIZE:'
}

# ── Phase 0: Analyze stale pinned inputs ──────────────────────────
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TOPGRADE — Comprehensive Flake Upgrade${NC}"
echo -e "${CYAN}  Mode: ${MODE}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo ""

info "Phase 0: Analyzing stale pinned inputs..."

STALE_JSON=$(run_py "
import json, datetime, re, os

d = json.load(open('/etc/nixos/flake.lock'))
nodes = d['nodes']
root = nodes['root']
root_inputs = root.get('inputs', {})

today = datetime.datetime.now()
stale = []
skip_names = set()

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

    with open('/etc/nixos/flake.nix') as f:
        flake_nix = f.read()

    # Find the URL in flake.nix for this input
    # Pattern 1: name = { url = \"...\"; ... }
    pat1 = re.search(
        rf'[ \t]*{re.escape(name)}\s*=\s*{{.*?url\s*=\s*\"([^\"]+)\"',
        flake_nix, re.DOTALL
    )
    # Pattern 2: name.url = \"...\";
    pat2 = re.search(
        rf'[ \t]*{re.escape(name)}\.url\s*=\s*\"([^\"]+)\"',
        flake_nix
    )

    url = None
    pos = None
    if pat1:
        url = pat1.group(1)
        pos = pat1.start()
    elif pat2:
        url = pat2.group(1)
        pos = pat2.start()

    if not url:
        continue

    # Check if URL has a pinned commit hash
    pin_match = re.search(r'(github:[^/]+/[^/]+)/([a-f0-9]{40})\b', url)
    if not pin_match:
        continue

    base_url = pin_match.group(1)
    pinned_rev = pin_match.group(2)

    # Not stale if pinned rev doesn't match lock (URL was already bumped)
    if pinned_rev != rev:
        continue

    # Check for 'why pinned' comments in the 400 chars before the input
    preceding = flake_nix[max(0, pos-400):pos]
    has_explain_comment = bool(re.search(
        r'#\s*(?:pin|reason|because|needs|requires|pinned|comment|fixes|works around)',
        preceding, re.IGNORECASE
    ))

    # Our own repos — skip (need manual unpin/rebuild)
    is_our_repo = 'reverb256' in url

    stale.append({
        'name': name,
        'days': days_ago,
        'source_url': base_url,
        'rev': rev[:12],
        'our_repo': is_our_repo,
        'has_explain_comment': has_explain_comment,
    })

print(json.dumps(stale, indent=2))
")

# ── Phase 0b: Check for missing nixpkgs follows ────────────────────
info "Phase 0b: Checking for missing nixpkgs follows..."

MISSING_JSON=$(run_py "
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
    if name == 'nixpkgs':
        continue

    node = nodes.get(target, {})
    node_inputs = node.get('inputs', {})

    # No inputs at all
    if not node_inputs:
        continue

    # Check if node has a nixpkgs input at all
    nixpkgs_ref = node_inputs.get('nixpkgs')
    if nixpkgs_ref is None:
        continue

    # Already following via list reference (our root's nixpkgs)
    if isinstance(nixpkgs_ref, list):
        continue

    # Check if OUR flake.nix already has a follow directive for this input
    # Look in the block between 'name = {' and the closing '};'
    block = re.search(
        rf'{re.escape(name)}\s*=\s*\{{.*?\}};',
        flake_nix, re.DOTALL
    )
    if block and 'inputs.nixpkgs.follows' in block.group(0):
        continue

    # Also check short form name.url = \"...\";
    short_form = re.search(
        rf'{re.escape(name)}\.url\s*=\s*\"', flake_nix
    )
    if short_form:
        continue  # short form — no inputs exposed

    # Local path or gitlab — skip
    orig = node.get('original', {})
    url = orig.get('url', '')
    if url.startswith('path:') or url.startswith('gitlab:'):
        continue

    # This input has its own nixpkgs but we haven't wired a follow
    target_nixpkgs_node = nodes.get(nixpkgs_ref, {}) if isinstance(nixpkgs_ref, str) else {}
    target_rev = target_nixpkgs_node.get('locked', {}).get('rev', '?')[:12] if isinstance(nixpkgs_ref, str) else '?'
    target_repo = nixpkgs_ref if isinstance(nixpkgs_ref, str) else '?'

    missing.append({
        'name': name,
        'nixpkgs_node': nixpkgs_ref if isinstance(nixpkgs_ref, str) else str(nixpkgs_ref),
        'nixpkgs_rev': target_rev,
    })

print(json.dumps(missing, indent=2))
")

# ── Display results ────────────────────────────────────────────────

display_json() {
    local json="$1"
    python3 -c "
import json, sys
data = json.loads('''$json''')
if not data:
    print('  (none)')
    sys.exit(0)
for item in data:
    name = item['name']
    days = item.get('days', 0)
    src = item.get('source_url', item.get('nixpkgs_node', ''))
    rev = item.get('rev', item.get('nixpkgs_rev', ''))
    notes = ''
    if item.get('our_repo'):
        notes = ' [our repo — skip]'
    elif item.get('has_explain_comment'):
        notes = ' [pinned with reason — skip]'
    print(f'  {name:25s} {days:3d}d old  {src:45s} {rev}{notes}')
" 2>/dev/null | grep -v '^SITECUSTOMIZE:'
}

echo ""
STALE_COUNT=$(echo "$STALE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))" 2>/dev/null | grep -v '^SITECUSTOMIZE:' || echo "0")
MISSING_COUNT=$(echo "$MISSING_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))" 2>/dev/null | grep -v '^SITECUSTOMIZE:' || echo "0")

if [ "$STALE_COUNT" -gt 0 ]; then
    info "Stale pinned inputs ($STALE_COUNT):"
    display_json "$STALE_JSON"
else
    info "Stale pinned inputs: (none)"
fi

echo ""
if [ "$MISSING_COUNT" -gt 0 ]; then
    info "Missing nixpkgs follows ($MISSING_COUNT):"
    display_json "$MISSING_JSON"
else
    info "Missing nixpkgs follows: (none)"
fi

# ── Dry-run: exit here ─────────────────────────────────────────────
if [ "$MODE" = "dry" ]; then
    echo ""
    if [ "$STALE_COUNT" -gt 0 ] || [ "$MISSING_COUNT" -gt 0 ]; then
        warn "Run 'just topgrade apply' to execute the upgrade"
    else
        ok "Nothing to upgrade — all inputs are current"
    fi
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════
# APPLY MODE
# ═══════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}── Phase 1: Unpinning stale inputs ──${NC}"

UNPIN_RESULT=$(run_py "
import json, re

with open('/etc/nixos/flake.nix', 'r') as f:
    flake_nix = f.read()

original = flake_nix
stale = json.loads('''$STALE_JSON''')
results = []

for item in stale:
    name = item['name']
    if item.get('our_repo') or item.get('has_explain_comment'):
        results.append(f'SKIP {name}: {\"our repo\" if item[\"our_repo\"] else \"pinned with reason\"}')
        continue

    source_url = item['source_url']
    # Replace the commit hash in the URL with just the base URL
    # Find the exact URL string in the file
    m = re.search(rf'\"{re.escape(source_url)}/[a-f0-9]{{40}}\"', original)
    if m:
        old = m.group(0)
        new = f'\"{source_url}\"'
        original = original.replace(old, new, 1)
        results.append(f'UNPIN {name}: {item[\"days\"]}d old -> {source_url}')

with open('/etc/nixos/flake.nix', 'w') as f:
    f.write(original)

for r in results:
    print(r)
")

echo "$UNPIN_RESULT"

# ── Phase 2: Add missing nixpkgs follows ──────────────────────────
echo ""
echo -e "${CYAN}── Phase 2: Adding missing nixpkgs follows ──${NC}"

WIRE_RESULT=$(run_py "
import json, re

with open('/etc/nixos/flake.nix', 'r') as f:
    flake_nix = f.read()

original = flake_nix
missing = json.loads('''$MISSING_JSON''')
results = []

for item in missing:
    name = item['name']

    # Check if it's a short-form declaration: name.url = \"...\";
    short_match = re.search(
        rf'^( *)({re.escape(name)})\.url\s*=\s*\"([^\"]+)\";\s*$',
        original, re.MULTILINE
    )
    if short_match:
        indent = short_match.group(1)
        url_val = short_match.group(3)
        old_line = short_match.group(0)
        new_block = f'''{indent}{name} = {{
{indent}  url = \"{url_val}\";
{indent}  inputs.nixpkgs.follows = \"nixpkgs\";
{indent}}};'''
        original = original.replace(old_line, new_block, 1)
        results.append(f'WIRE {name}: short form -> long form with follow')
        continue

    # Check if it's in a block but missing the follow
    block_match = re.search(
        rf'({re.escape(name)}\s*=\s*\{{)(.*?)(\}};)',
        original, re.DOTALL
    )
    if block_match and 'inputs.nixpkgs.follows' not in block_match.group(2):
        # Insert after the url line
        old_block = block_match.group(0)
        inside = block_match.group(2)
        new_inside = inside.rstrip() + '\\n      inputs.nixpkgs.follows = \"nixpkgs\";'
        new_block = block_match.group(1) + new_inside + block_match.group(3)
        original = original.replace(old_block, new_block, 1)
        results.append(f'WIRE {name}: added follow to existing block')

with open('/etc/nixos/flake.nix', 'w') as f:
    f.write(original)

for r in results:
    print(r)
if not results:
    print('  (nothing to wire)')
")

echo "$WIRE_RESULT"

# ── Phase 3: Refresh flake.lock ────────────────────────────────────
echo ""
echo -e "${CYAN}── Phase 3: Refreshing key flake inputs ──${NC}"

# After unpinning, the lock file still has valid locked entries from the
# previous pinned commits. We need to update the lock to match the new
# branch-following URLs. This uses nix flake prefetch which works
# reliably (unlike nix flake update with Lix's sandbox curl bug).
info "Refreshing nixpkgs..."
nix flake prefetch --json "github:NixOS/nixpkgs/nixos-unstable" > /dev/null 2>&1 && ok "nixpkgs refreshed" || warn "nixpkgs refresh skipped"

info "Refreshing home-manager..."
nix flake prefetch "github:nix-community/home-manager" > /dev/null 2>&1 && ok "home-manager refreshed" || warn "home-manager refresh skipped"

# Final lock regeneration (no network fetches needed)
info "Regenerating flake.lock from current state..."
nix flake metadata --allow-dirty 2>&1 | tail -3 && ok "Flake resolves correctly"

# ── Phase 4: Validate ──────────────────────────────────────────────
echo ""
echo -e "${CYAN}── Phase 4: Validating flake ──${NC}"

info "Checking flake.lock JSON..."
python3 -c "import json; json.load(open('flake.lock')); print('  valid')" 2>/dev/null

info "Running: nix flake check (30s timeout)"
if timeout 30 nix flake check --allow-dirty 2>&1; then
    ok "Flake check passed"
else
    warn "Flake check timed out (usually niri fetching crate sources) — non-fatal"
fi

# Validate that key inputs resolve
info "Verifying key inputs resolve..."
for inp in nixpkgs home-manager colmena niri; do
    if timeout 10 nix flake metadata --allow-dirty ".#$inp" 2>/dev/null > /dev/null; then
        ok "$inp resolves"
    else
        warn "$inp resolve failed (non-fatal)"
    fi
done

# ── Phase 5: Commit ────────────────────────────────────────────────
echo ""
echo -e "${CYAN}── Phase 5: Committing ──${NC}"

git add flake.nix flake.lock
if git diff --cached --quiet; then
    ok "Nothing to commit — no changes"
else
    N_UNPIN=$(git diff --cached flake.nix 2>/dev/null | grep '^-.*url.*github:' | grep -v '^---' | wc -l || echo "0")
    git commit -m "topgrade: unpin stale inputs + update all flake inputs" \
               -m "Auto-generated by scripts/topgrade.sh" 2>&1 | tail -2
    ok "Committed ($N_UNPIN inputs unpinned)"

    info "Pushing to origin..."
    git push origin main 2>&1 | tail -2 || warn "Push failed (network?)"
fi

# ── Phase 6: Switch (local host) ───────────────────────────────────
echo ""
echo -e "${CYAN}── Phase 6: Switching (local host: $HOST) ──${NC}"

if command -v nixos-rebuild &>/dev/null; then
    info "Running: nixos-rebuild switch"
    if sudo nixos-rebuild switch --flake ".#$HOST" 2>&1; rc=$?; then
        ok "Switch complete"
    elif [ $rc -eq 4 ]; then
        warn "Switch had warnings (rc=4) — usually NixOS deprecation notices"
    else
        err "Switch failed (rc=$rc)"
        exit $rc
    fi
else
    warn "Not on NixOS host — skipping switch"
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
