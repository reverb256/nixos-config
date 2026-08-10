#!/usr/bin/env bash
# Verify the repository-level GitHub Actions allowlist required by workflows.
# This policy lives in GitHub settings, not in the NixOS tree; keep this check
# beside the workflows so a policy reset is detected before CI is trusted.
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-reverb256/nixos-config}"
command -v gh >/dev/null || { echo "check-actions-policy: gh is required" >&2; exit 127; }
[[ -n "${GH_TOKEN:-}" ]] || { echo "check-actions-policy: GH_TOKEN is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "check-actions-policy: jq is required" >&2; exit 127; }

PERMISSIONS=$(gh api "repos/$REPO/actions/permissions")
SELECTED=$(gh api "repos/$REPO/actions/permissions/selected-actions")

if [[ "$(jq -r '.enabled' <<<"$PERMISSIONS")" != true ]]; then
  echo "ERROR: GitHub Actions are disabled for $REPO" >&2
  exit 1
fi
if [[ "$(jq -r '.allowed_actions' <<<"$PERMISSIONS")" != selected ]]; then
  echo "ERROR: expected selected Actions policy for $REPO" >&2
  exit 1
fi

for pattern in 'cachix/*' 'peter-evans/*'; do
  if ! jq -e --arg pattern "$pattern" '.patterns_allowed | index($pattern)' <<<"$SELECTED" >/dev/null; then
    echo "ERROR: missing selected-action allowlist pattern: $pattern" >&2
    exit 1
  fi
done

if [[ "$(jq -r '.github_owned_allowed' <<<"$SELECTED")" != true ]]; then
  echo "ERROR: GitHub-owned actions are not allowed" >&2
  exit 1
fi

printf 'OK: %s allows GitHub-owned actions, cachix/*, and peter-evans/*\n' "$REPO"
