#!/usr/bin/env bash
# Network-dependent cache provenance audit for issue #415.
#
# This intentionally does not build or substitute. It evaluates host toplevel
# derivations, samples relevant recursive derivation outputs, and queries
# configured caches' narinfo endpoints. A miss is classified as expected only
# when its store name is an intentional custom or aggregate system output.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

read -r -a HOSTS <<< "${CACHE_AUDIT_HOSTS:-zephyr forge sentry nexus}"
MAX_OUTPUTS=${CACHE_AUDIT_MAX_OUTPUTS:-25}
AUDIT_NAME_REGEX=${CACHE_AUDIT_NAME_REGEX:-'nixos-system|glibc|gcc|stdenv|python|torch|pytorch|cuda|cudnn|rocm|hip|llama|niri|qtbase|gtk|webkit|gradio|sentence-transformers'}

for command in nix curl jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "cache-audit: $command is required" >&2
    exit 127
  }
done

# The audit is intentionally impure: it reads the checked-out policy file and
# probes remote caches. Normal `nix flake check` remains pure/offline-first.
POLICY_JSON=$(nix eval --impure --json --expr 'import ./contracts/cache-policy.nix')
mapfile -t CACHES < <(jq -r '.substituters[] | split("?")[0]' <<< "$POLICY_JSON")
mapfile -t CUSTOM_NAMES < <(jq -r '.intentionalCustomPackages[]' <<< "$POLICY_JSON")

is_custom_name() {
  local output=$1 name
  for name in "${CUSTOM_NAMES[@]}"; do
    [[ "$output" == *"-${name}-"* || "$output" == *"-${name}"* ]] && return 0
  done
  return 1
}

is_aggregate_name() {
  local output=$1
  [[ "$output" == *"-nixos-system-"* \
    || "$output" == *"-activation-script"* \
    || "$output" == *"-etc"* \
    || "$output" == *"-nix.conf"* ]]
}

reachable_caches=()
for cache in "${CACHES[@]}"; do
  if curl -fsS --max-time 15 "$cache/nix-cache-info" >/dev/null 2>&1; then
    reachable_caches+=("$cache")
  else
    printf 'cache-audit: UNREACHABLE %s\n' "$cache" >&2
  fi
done

if [ "${#reachable_caches[@]}" -eq 0 ]; then
  echo "cache-audit: no configured caches are reachable" >&2
  exit 2
fi

undeclared_misses=0
probe_output() {
  local output=$1 hash cache hit=0
  hash=${output#/nix/store/}
  hash=${hash%%-*}
  for cache in "${reachable_caches[@]}"; do
    if curl -fsS --max-time 15 "$cache/$hash.narinfo" >/dev/null 2>&1; then
      # This is metadata presence, not signature verification. The Nix daemon
      # performs signature verification during an actual substitution because
      # require-sigs=true; probing every narinfo through a remote Nix store can
      # block for minutes on unavailable CDN paths.
      printf '    %-36s METADATA HIT\n' "$cache"
      hit=1
    fi
  done
  if [ "$hit" -eq 0 ]; then
    if is_custom_name "$output"; then
      printf '    %-36s EXPECTED CUSTOM MISS\n' "$(basename "$output")"
    elif is_aggregate_name "$output"; then
      printf '    %-36s EXPECTED AGGREGATE MISS\n' "$(basename "$output")"
    else
      printf '    %-36s UNDECLARED MISS\n' "$(basename "$output")"
      undeclared_misses=$((undeclared_misses + 1))
    fi
  fi
}

for host in "${HOSTS[@]}"; do
  echo "=== $host ==="
  if ! drv=$(nix eval --raw ".#nixosConfigurations.${host}.config.system.build.toplevel.drvPath"); then
    echo "cache-audit: EVAL_FAILED for $host" >&2
    exit 3
  fi
  echo "  drv: $drv"

  # `nix derivation show -r` reports build-time derivation dependencies, not a
  # realized runtime closure. We deliberately sample relevant derivation names
  # here; after a build, a future phase should audit `nix path-info --recursive`
  # for the exact realized closure.
  top_outputs=$(nix derivation show "$drv" | jq -r '.[].outputs[] | .path')
  selected_outputs=$(nix derivation show -r "$drv" \
    | jq -r --arg pattern "$AUDIT_NAME_REGEX" '
        to_entries[]
        | select(.value.name | test($pattern; "i"))
        | .value.outputs[]
        | .path
      ' \
    | sort -u \
    | awk -v max="$MAX_OUTPUTS" 'NR <= max')
  outputs=$(printf '%s\n%s\n' "$top_outputs" "$selected_outputs" | sed '/^$/d' | sort -u)
  if [ -z "$outputs" ]; then
    echo "cache-audit: no selected outputs for $host" >&2
    exit 4
  fi
  count=$(wc -l <<< "$outputs")
  echo "  probing $count selected outputs (max $MAX_OUTPUTS)"
  while IFS= read -r output; do
    [ -n "$output" ] || continue
    probe_output "$output"
  done <<< "$outputs"
done

if [ "$undeclared_misses" -gt 0 ]; then
  echo "cache-audit: FAILED — $undeclared_misses undeclared cache miss(es)" >&2
  exit 5
fi
echo "cache-audit: PASS — no undeclared misses in sampled outputs"
