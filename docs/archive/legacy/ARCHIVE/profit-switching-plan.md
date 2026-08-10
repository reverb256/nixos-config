# Profit Switching Plan — Kryptex Auto-Exchange Pools

**Created:** 2026-04-25 | **Status:** Planning

## Overview

Build a K8s-native profit switcher that polls coin profitability, decides the best coin per GPU group, and reconfigures mining pods to mine the most profitable coin on Kryptex's auto-exchange pools.

## Key Insight

Kryptex does NOT have a profit-switching stratum. Each coin has its own pool endpoint. Their "auto-exchange" converts mined coins to BTC/USDT at payout — it doesn't switch coins. We must implement switching ourselves.

## GPU Groups & Miner Compatibility

| Group | GPUs | Miner (NVIDIA) | Miner (AMD) |
|-------|------|----------------|-------------|
| forge-nvidia | 2× RTX 4060 | Rigel | — |
| nexus | 1× RTX 3060 Ti | Rigel | — |
| zephyr-3090 | 1× RTX 3090 | Rigel | — |
| forge-amd | 2× RX 5700 XT | — | TeamRedMiner |

## Kryptex GPU Coins (with auto-exchange)

| Coin | Algo | Pool Host (US) | Port | TLS Port | Rigel Flag | TRM Flag |
|------|------|----------------|------|----------|------------|----------|
| RVN | kawpow | rvn-us.kryptex.network | 7031 | 8031 | `-a kawpow --coin rvn` | `-a kawpow` |
| CFX | octopus | cfx-us.kryptex.network | 7027 | 8027 | `-a octopus --coin cfx` | ✗ |
| ERG | autolykos2 | erg-us.kryptex.network | 7021 | — | `-a autolykos2` | `-a autolykos2` |
| NEXA | nexapow | nexa-us.kryptex.network | 7026 | — | `-a nexapow` | ✗ |
| XNA | kawpow | xna-us.kryptex.network | 7024 | — | `-a kawpow --coin xna` | `-a kawpow` |
| XEL | xelishashv3 | xel-us.kryptex.network | TBD | — | TBD | ✗ |
| IRON | fishhash | iron-us.kryptex.network | TBD | — | TBD | ✗ |

**AMD-compatible coins**: RVN, ERG, XNA (kawpow + autolykos2 only)
**NVIDIA-compatible coins**: All above

## Profitability Data Source

**WhatToMine API** (`https://whattomine.com/coins.json`)

Returns per-coin: `btc_revenue`, `algorithm`, `difficulty`, `exchange_rate`

The revenue values are normalized per GPU hashrate unit. We'll use `btc_revenue` for comparison since all Kryptex auto-exchange pools pay out in BTC equivalent.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  PROFIT SWITCHER (CronJob)               │
│                  Runs on nexus every 5 min                │
│                                                          │
│  1. Fetch WhatToMine /coins.json                         │
│  2. Filter to Kryptex-supported coins                    │
│  3. Score per GPU group (NVIDIA vs AMD compatibility)    │
│  4. Update ConfigMap "mining-profit-config"              │
│  5. For each GPU group, patch deployment args            │
└─────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ ConfigMap        │ │ Deployment       │ │ Deployment       │
│ mining-profit-   │ │ gpu-miner-forge- │ │ gpu-miner-forge- │
│ config           │ │ nvidia-0         │ │ amd-0            │
│                  │ │                  │ │                  │
│ nvidia-best:     │ │ args: rigel      │ │ args: teamred... │
│   coin: rvn      │ │  -a kawpow       │ │  -a kawpow       │
│   algo: kawpow   │ │  -o rvn-us...    │ │  -o rvn-us...    │
│   pool: ...      │ │                  │ │                  │
│ amd-best:        │ └─────────────────┘ └─────────────────┘
│   coin: rvn      │
│   algo: kawpow   │
│   pool: ...      │
└─────────────────┘
```

## Components

### 1. Profit Config ConfigMap (`mining-profit-config`)

Stores the current best coin per GPU group. The switcher writes this, deployments can reference it.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mining-profit-config
  namespace: mining
data:
  nvidia-best.json: |
    {"coin": "rvn", "algo": "kawpow", "pool": "stratum+tcp://rvn-us.kryptex.network:7031", ...}
  amd-best.json: |
    {"coin": "rvn", "algo": "kawpow", "pool": "stratum+tcp://rvn-us.kryptex.network:7031", ...}
  last-updated: "2026-04-25T12:00:00Z"
  switch-history.json: |
    [{"time": "...", "from": "rvn", "to": "cfx", "group": "nvidia", "reason": "profit +15%"}]
```

### 2. Profit Switcher (CronJob on nexus)

NixOS service / K8s CronJob that:
- Polls WhatToMine API every 5 minutes
- Filters to Kryptex-supported coins per GPU group
- Applies hysteresis (only switch if new coin is >10% better, to avoid thrashing)
- Updates the ConfigMap
- Restarts affected deployments via `kubectl rollout restart`

**Hysteresis rules:**
- Minimum hold time: 30 minutes (don't switch more often)
- Switch threshold: new coin must be >10% more profitable
- Cooldown after switch: 15 minutes

### 3. Pod Wrapper Script

Each mining pod already downloads all miners via `downloadAllMiners`. Add a wrapper that:
1. Reads current config from ConfigMap (via API or env injection)
2. Selects the correct miner binary and args
3. Executes the miner
4. Watches for ConfigMap changes (via API poll)
5. On change: graceful shutdown → restart with new config

This avoids full pod restarts and makes switching faster (~30s vs ~2min).

### 4. Profit Switcher RBAC

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: profit-switcher
  namespace: mining
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "update", "patch"]
    resourceNames: ["mining-profit-config"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "patch"]
```

## Implementation Phases

### Phase 1: Data Collection (Day 1)
- Create the `mining-profit-config` ConfigMap
- Build a script that polls WhatToMine and writes profitability to ConfigMap
- Deploy as a CronJob or systemd timer
- Log profitability data for analysis

### Phase 2: Manual Switching (Day 2)
- Script that reads ConfigMap and patches deployment args
- Manual trigger mode: `kubectl exec` or `just switch-coin rvn`
- Test switching on one forge-nvidia pod
- Verify miner restarts correctly with new algo

### Phase 3: Automated Switching (Day 3)
- Combine data collection + deployment patching into one CronJob
- Add hysteresis logic (hold time, threshold)
- Add switch history logging
- Enable on all GPU groups

### Phase 4: In-Pod Switching (Day 4-5)
- Wrapper script that polls ConfigMap and switches miner without pod restart
- Faster switching (~30s vs ~2min pod restart)
- Signal handling for graceful miner shutdown
- Deploy to all pods

### Phase 5: Observability (Day 6)
- Grafana dashboard: current coin per GPU, profitability over time, switch history
- Prometheus metrics: `mining_profit_btc_per_day`, `mining_current_coin`, `mining_switches_total`
- Alerts: if profitability drops below threshold, if switcher fails

## Estimated Profitability (WhatToMine, April 2026)

Top GPU-mineable coins on Kryptex by BTC revenue per day:

| Rank | Coin | Algo | BTC/Day | Notes |
|------|------|------|---------|-------|
| 1 | Neoxa (XNA) | kawpow | 0.0000074 | Low market cap, volatile |
| 2 | Kerrigan | kawpow | 0.0000073 | Not on Kryptex |
| 3 | Quai | kawpow | 0.00000631 | On Kryptex |
| 4 | Xelis | xelishashv3 | 0.00000518 | On Kryptex |
| 5 | IronFish | fishhash | 0.00000482 | On Kryptex |
| 6 | RVN | kawpow | 0.00000424 | Most stable |
| 7 | Nexa | nexapow | 0.00000325 | On Kryptex |
| 8 | Ergo | autolykos2 | 0.0000025 | Low revenue |

**Note:** WhatToMine's default revenue is for a generic GPU. Actual revenue depends on hashrate per algorithm. RTX 3090 gets ~80 MH/s on kawpow and octopus, which changes relative rankings.

## File Locations

| Component | Path |
|-----------|------|
| Profit switcher script | `kubernetes/modules/profit-switcher.nix` |
| GPU miner config | `kubernetes/modules/gpu-miners.nix` |
| Mining base config | `kubernetes/modules/mining.nix` |
| Mining dashboard | `kubernetes/modules/monitoring-dashboards.nix` |
| Compute market module | `/data/projects/own/compute-market/modules/` |
