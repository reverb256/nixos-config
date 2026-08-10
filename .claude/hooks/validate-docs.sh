#!/usr/bin/env bash
# Documentation validation hook.
# The repository verification suite owns the active-document policy; this hook
# exists as a convenient editor/agent entry point and must not have a second,
# conflicting policy.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"
exec ./docs/meta/VERIFICATION-SUITE/run.sh
