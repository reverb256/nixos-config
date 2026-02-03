#!/usr/bin/env bash

# Check for secrets in git history and current files
# Usage: ./check-for-secrets.sh

set -euo pipefail

# Patterns to search for
PATTERNS=(
    "sk-[a-zA-Z0-9]{48}"       # OpenAI API key
    "pk-[a-zA-Z0-9]{32}"       # API keys (generic)
    "secret_key.*[a-zA-Z0-9]{32}" # Secret keys
    "access_key.*[a-zA-Z0-9]{20}" # Access keys
    "wallet.*[a-zA-Z0-9]{34}"  # Bitcoin/Ethereum addresses
    "0x[a-zA-Z0-9]{40}"        # Ethereum addresses
    "mnemonic.*[a-zA-Z ]{100}" # BIP-39 mnemonics
)

echo "Checking for secrets in git history..."

# Check git history
for pattern in "${PATTERNS[@]}"; do
    if git log --grep="$pattern" --oneline 2>/dev/null; then
        echo "⚠️  WARNING: Pattern '$pattern' found in git history"
    fi
done

echo "Checking for secrets in current files..."

# Check current files (ignore .age files which are encrypted)
grep -rE "(${PATTERNS[*]})" --exclude="*.age" --exclude-dir=".git" . 2>/dev/null || true

echo "Checking for unencrypted secrets..."
if ls secrets/*.key secrets/*.txt 2>/dev/null; then
    echo "⚠️  WARNING: Unencrypted secret files found in secrets/ directory"
fi

echo "Checking gitignore patterns..."
if ! grep -q "*.age" .gitignore; then
    echo "⚠️  WARNING: .gitignore should ignore *.age files"
fi

