#!/usr/bin/env bash
# Non-destructive deployment-script tests. Never invokes SSH, Nix, or Colmena.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$ROOT/scripts/deploy/nexus-dispatch.sh"
CANARY="$ROOT/scripts/deploy-canary.sh"

bash -n "$DISPATCH"
bash -n "$CANARY"

help_output="$(bash "$DISPATCH" --help)"
grep -q 'DEPLOY_LOCK_FILE' <<<"$help_output"
grep -q 'DEPLOY_RESULT_DIR' <<<"$help_output"

if bash "$DISPATCH" --target invalid >/dev/null 2>&1; then
  echo "invalid target unexpectedly succeeded" >&2
  exit 1
fi

command -v jq >/dev/null
sample=$(jq -cn \
  --arg run_id test \
  --arg target zephyr \
  --arg canonical_commit abc \
  --arg status success \
  --arg evidence_status complete \
  --arg started_at now \
  --arg finished_at now \
  --arg message ok \
  --argjson exit_code 0 \
  --argjson active_generations '{"zephyr":{"generation":"/nix/store/test","commit":"abc"}}' \
  '{schema: 1, run_id: $run_id, target: $target, canonical_commit: $canonical_commit, status: $status, evidence_status: $evidence_status, exit_code: $exit_code, started_at: $started_at, finished_at: $finished_at, message: $message, active_generations: $active_generations}')
jq -e '.schema == 1 and .status == "success" and .active_generations.zephyr.commit == "abc"' <<<"$sample" >/dev/null

echo "deployment script tests passed"
