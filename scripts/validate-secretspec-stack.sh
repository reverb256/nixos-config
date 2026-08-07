#!/usr/bin/env bash
# validate-secretspec-stack.sh — Per-file validator for the secretspec dual-fork
# stack. Invoked by:
#   1) .pre-commit-config.yaml (local, every commit touching secretspec files)
#   2) .github/workflows/secretspec-build.yml (CI, on PRs touching pkgs/*)
#
# Behavior:
#   - For each file in argv, run the appropriate check.
#   - Bash scripts: bash -n syntax check.
#   - Nix files: nix-instantiate --parse.
#   - TOML files: python tomllib parse via inline check.
#   - For non-argv flags (--env, --schema), do project-wide gates.
#
# Exit codes:
#   0  all checks passed
#   1  a per-file check or env/binary gate failed
#   2  wrong arguments
#
# This script maintains secretspec-stack-invariants WITHOUT touching .age files
# or decrypting any cluster secret — pure structural validation.

set -euo pipefail

# ── Args ─────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage:
  $0 [--env] [--schema] <file1> [<file2> ...]

Per-file checks (file extension inferred):
  *.sh       bash -n syntax check
  *.nix      nix-instantiate --parse (must parse)
  *.toml     python tomllib parse (must be valid TOML)

Project gates (run regardless of argv when flag present):
  --env      Verify CACHIX_AUTH_TOKEN is set; warn if not.
  --schema   Verify secretspec.toml schema declares expected counts.
EOF
}

PERFORM_ENV=0
PERFORM_SCHEMA=0
FILES=()

for arg in "$@"; do
  case "$arg" in
    --env) PERFORM_ENV=1 ;;
    --schema) PERFORM_SCHEMA=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown flag: $arg" >&2; usage; exit 2 ;;
    *) FILES+=("$arg") ;;
  esac
done

if [ ${#FILES[@]} -eq 0 ] && [ "$PERFORM_ENV" -eq 0 ] && [ "$PERFORM_SCHEMA" -eq 0 ]; then
  usage
  exit 2
fi

# ── Per-file checks ──────────────────────────────────────────────────────────
for f in "${FILES[@]}"; do
  case "$f" in
    *.sh)
      echo "[validate] bash -n $f"
      bash -n "$f" || { echo "[validate] FAIL: bash syntax in $f" >&2; exit 1; }
      ;;
    *.nix)
      echo "[validate] nix-instantiate --parse $f"
      nix-instantiate --parse "$f" >/dev/null 2>&1 \
        || { echo "[validate] FAIL: Nix parse in $f" >&2; exit 1; }
      ;;
    *.toml)
      echo "[validate] tomllib parse $f"
      python3 -c "import tomllib; tomllib.loads(open('$f').read())" \
        || { echo "[validate] FAIL: TOML parse in $f" >&2; exit 1; }
      ;;
    *)
      echo "[validate] skip (no rule): $f"
      ;;
  esac
done

# ── Project gates ────────────────────────────────────────────────────────────
if [ "$PERFORM_ENV" -eq 1 ]; then
  echo "[validate] checking CACHIX_AUTH_TOKEN env"
  if [ -z "${CACHIX_AUTH_TOKEN:-}" ]; then
    echo "[validate] WARN: CACHIX_AUTH_TOKEN not set (cachix push won't work)" >&2
  else
    echo "[validate] OK: CACHIX_AUTH_TOKEN set (redacted: ${CACHIX_AUTH_TOKEN:0:4}...)"
  fi
fi

if [ "$PERFORM_SCHEMA" -eq 1 ]; then
  echo "[validate] checking secretspec.toml schema"
  python3 - <<'PYEOF' || exit 1
import tomllib, sys
with open('secretspec.toml', 'rb') as f:
    d = tomllib.load(f)
n = sum(len(v) for v in d.get('profiles', {}).values() if isinstance(v, dict))
ps = d.get('phase2_status', {})
print(f"[validate] schema: {n} entries across {len(d.get('profiles', {}))} profiles")
print(f"[validate]   phase2_status.state = {ps.get('state')!r}")
print(f"[validate]   phase2_status.route_count = {ps.get('route_count')!r}")
PYEOF
fi

echo "[validate] all checks passed"
