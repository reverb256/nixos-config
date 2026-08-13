#!/usr/bin/env bash
# Dendritic gate: prove all four host evaluators and Colmena evaluate.
# This intentionally evaluates derivations only; it does not build or deploy.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

for host in zephyr nexus forge sentry; do
  echo "[dendritic] evaluating $host"
  dendritic_drv=$(nix eval --raw --no-warn-dirty \
    ".#nixosConfigurations.${host}.config.system.build.toplevel.drvPath")
  echo "  $dendritic_drv"

  dendritic_name=$(nix eval --raw --no-warn-dirty \
    ".#nixosConfigurations.${host}.config.networking.hostName")
  dendritic_state=$(nix eval --raw --no-warn-dirty \
    ".#nixosConfigurations.${host}.config.system.stateVersion")
  echo "  hostName=$dendritic_name stateVersion=$dendritic_state"
done

echo "[dendritic] evaluating parity check"
nix eval --no-warn-dirty '.#checks.x86_64-linux.dendritic-parity' >/dev/null

echo "[dendritic] evaluating Colmena hive"
nix eval --no-warn-dirty '.#colmenaHive' >/dev/null

nix flake check --no-build --show-trace

echo "[dendritic] host evaluator gate passed"
