#!/usr/bin/env bash
# Phase 1 gate: prove all four dendritic host evaluators and Colmena evaluate.
# This intentionally evaluates derivations only; it does not build or deploy.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

for host in zephyr nexus forge sentry; do
  echo "[dendritic] evaluating $host"
  dendritic_drv=$(nix eval --raw --no-warn-dirty \
    ".#nixosConfigurations.${host}.config.system.build.toplevel.drvPath")
  echo "  $dendritic_drv"

  echo "[classic-compat] evaluating $host"
  classic_drv=$(nix eval --raw --no-warn-dirty \
    ".#classicNixosConfigurations.${host}.config.system.build.toplevel.drvPath")
  echo "  $classic_drv"

  dendritic_name=$(nix eval --raw --no-warn-dirty \
    ".#nixosConfigurations.${host}.config.networking.hostName")
  classic_name=$(nix eval --raw --no-warn-dirty \
    ".#classicNixosConfigurations.${host}.config.networking.hostName")
  dendritic_state=$(nix eval --raw --no-warn-dirty \
    ".#nixosConfigurations.${host}.config.system.stateVersion")
  classic_state=$(nix eval --raw --no-warn-dirty \
    ".#classicNixosConfigurations.${host}.config.system.stateVersion")

  if [[ "$dendritic_name" != "$classic_name" || "$dendritic_state" != "$classic_state" ]]; then
    echo "[dendritic] ERROR: $host compatibility contract differs" >&2
    exit 1
  fi
  echo "[dendritic] $host evaluator contract parity: PASS"
done

echo "[classic-compat] verifying namespace entries"
classic_hosts=$(nix eval --json --no-warn-dirty \
  --apply 'n: builtins.attrNames n' \
  '.#classicNixosConfigurations' \
  | jq -r 'sort | join(" ")')
if [[ "$classic_hosts" != "forge nexus sentry zephyr" ]]; then
  echo "[classic-compat] ERROR: expected all four entries, got: $classic_hosts" >&2
  exit 1
fi

echo "[dendritic] evaluating parity check"
nix eval --no-warn-dirty '.#checks.x86_64-linux.dendritic-parity' >/dev/null

echo "[dendritic] evaluating Colmena hive"
nix eval --no-warn-dirty '.#colmenaHive' >/dev/null
nix flake check --no-build --show-trace

echo "[dendritic] Phase 1 evaluator gate passed"
