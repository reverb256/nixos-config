#!/usr/bin/env bash
# Query local miner and output hashrate for starship prompt
# Supports: srbminer (API ports 21550+), lolminer (API port 3333)

set -euo pipefail

for port in 21550 21551; do
  if data=$(curl -sf --max-time 1 "http://localhost:$port/" 2>/dev/null); then
    hash=$(echo "$data" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    hr = d.get('hashrate_total', d.get('hashrate', 0))
    if hr >= 1000000:
        print(f'{hr/1000000:.1f} GH/s')
    elif hr >= 1000:
        print(f'{hr/1000:.1f} MH/s')
    else:
        print(f'{hr:.0f} KH/s')
except:
    print('?')
" 2>/dev/null)
    if [ -n "$hash" ]; then
      echo "⛏ $hash"
      exit 0
    fi
  fi
done

if data=$(curl -sf --max-time 1 "http://localhost:3333/api/v1/status" 2>/dev/null); then
  hash=$(echo "$data" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    hr = d.get('hashrate', 0) or 0
    if hr >= 1000000:
        print(f'{hr/1000000:.1f} GH/s')
    elif hr >= 1000:
        print(f'{hr/1000:.1f} MH/s')
    else:
        print(f'{hr:.0f} KH/s')
except:
    print('?')
" 2>/dev/null)
  if [ -n "$hash" ]; then
    echo "⛏ $hash"
    exit 0
  fi
fi

exit 1
