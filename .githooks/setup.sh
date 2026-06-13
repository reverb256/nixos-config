#!/usr/bin/env bash
# Install git hooks for nixos-config development
# Run: .githooks/setup.sh
# This configures pre-commit hooks via:
#   1. pre-commit (recommended — run once, hooks auto-update)
#   2. Direct git hooks (fallback — no pre-commit binary needed)

set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo /etc/nixos)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Setting up nixos-config git hooks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Method 1: pre-commit (if available)
if command -v pre-commit &>/dev/null; then
    echo "  Found pre-commit — installing hooks..."
    pre-commit install
    echo "  ✓ pre-commit hooks installed"
    echo "  Hooks will run on every 'git commit'"
    echo "  Run 'pre-commit run --all' to check all files now"
    echo ""
    echo "  Tip: Install pre-commit.ci app for auto-checks on PRs:"
    echo "  https://github.com/apps/pre-commit-ci"
    exit 0
fi

# Method 2: Direct git hooks (no pre-commit binary)
echo "  pre-commit not found — installing direct git hooks..."
HOOKS_DIR=".git/hooks"

cat > "$HOOKS_DIR/pre-commit" << 'HOOKEOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=== pre-commit hooks (direct) ==="

# Nix syntax check
for f in $(git diff --cached --name-only --diff-filter=ACMT | grep '\.nix$'); do
    if ! nix-instantiate --parse "$f" > /dev/null 2>&1; then
        echo "ERROR: Parse failed for $f"
        exit 1
    fi
done

# Trailing whitespace
for f in $(git diff --cached --name-only --diff-filter=ACMT); do
    if grep -l '[[:space:]]$' "$f" > /dev/null 2>&1; then
        echo "ERROR: Trailing whitespace in $f"
        echo "  Run: sed -i 's/[[:space:]]*$//' $f"
        exit 1
    fi
done

# Large files
for f in $(git diff --cached --name-only --diff-filter=ACMT); do
    if [ -f "$f" ] && [ "$(stat -c%s "$f" 2>/dev/null)" -gt 1000000 ]; then
        echo "ERROR: Large file detected: $f (>1MB)"
        exit 1
    fi
done

echo "=== pre-commit checks passed ==="
HOOKEOF

chmod +x "$HOOKS_DIR/pre-commit"
echo "  ✓ Direct git hooks installed"
echo "  Run 'pre-commit run --all' once pre-commit is installed"
