#!/usr/bin/env python3
"""Profit switcher for Kryptex auto-exchange pools.
Polls WhatToMine API, calculates revenue per GPU group,
and patches mining deployments to mine the most profitable coin.
"""
import json, os, sys, time, subprocess, math
from datetime import datetime, timezone, timedelta

try:
    import requests
except ImportError:
    import urllib.request
    import urllib.error
    class _Requests:
        @staticmethod
        def get(url, timeout=30):
            req = urllib.request.Request(url)
            resp = urllib.request.urlopen(req, timeout=timeout)
            class R:
                status = resp.status
                @staticmethod
                def json():
                    return json.loads(resp.read())
                def raise_for_status(self):
                    if self.status >= 400:
                        raise Exception(f"HTTP {self.status}")
            return R()
    requests = _Requests()

REQUIRED_ENV = ["WALLET", "GPU_PROFILES", "KRYPTXEX_POOLS", "GPU_GROUPS", "WTM_NAMES"]
missing = [v for v in REQUIRED_ENV if v not in os.environ]
if missing:
    sys.exit(f"ERROR: Missing required env vars: {', '.join(missing)}")

WALLET = os.environ["WALLET"]
GPU_PROFILES = json.loads(os.environ["GPU_PROFILES"])
KRYPTXEX_POOLS = json.loads(os.environ["KRYPTXEX_POOLS"])
GPU_GROUPS = json.loads(os.environ["GPU_GROUPS"])
WTM_NAMES = json.loads(os.environ["WTM_NAMES"])
SWITCH_THRESHOLD = float(os.environ.get("SWITCH_THRESHOLD", "0.10"))
MIN_HOLD_MINUTES = int(os.environ.get("MIN_HOLD_MINUTES", "30"))
CONFIGMAP = "mining-profit-config"
NAMESPACE = "mining"


def log(msg):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    print(f"[{ts}] {msg}", flush=True)


def kubectl(args, input_data=None):
    cmd = ["kubectl", "-n", NAMESPACE] + args
    r = subprocess.run(cmd, capture_output=True, text=True, input=input_data)
    if r.returncode != 0:
        log(f"kubectl {' '.join(args)} failed: {r.stderr.strip()}")
        return None
    return r.stdout.strip()


def fetch_wtm():
    r = requests.get("https://whattomine.com/coins.json", timeout=30)
    r.raise_for_status()
    return r.json()["coins"]


def calc_revenue(coin_data, our_hashrate_hs):
    nethash = coin_data.get("nethash", 0)
    block_reward = coin_data.get("block_reward", 0)
    block_time = coin_data.get("block_time", 0)
    exchange_rate = coin_data.get("exchange_rate", 0)
    if not all([nethash, block_reward, block_time, exchange_rate, our_hashrate_hs]):
        return 0.0
    try:
        bt = float(block_time)
        if bt <= 0:
            return 0.0
        return (our_hashrate_hs / nethash) * block_reward * (86400.0 / bt) * exchange_rate
    except (ValueError, ZeroDivisionError):
        return 0.0


def get_configmap():
    out = kubectl(["get", "configmap", CONFIGMAP, "-o", "json"])
    if not out:
        return {}
    return json.loads(out).get("data", {})


def update_configmap(updates):
    current = get_configmap()
    patches = []
    for k, v in updates.items():
        op = "replace" if k in current else "add"
        patches.append({"op": op, "path": f"/data/{k}", "value": v})
    patch_json = json.dumps(patches)
    result = kubectl(["patch", "configmap", CONFIGMAP, "--type=json", "-p", patch_json])
    if result:
        log(f"ConfigMap updated: {list(updates.keys())}")
    return result


def restart_deployment(deploy_name, coin, group_name):
    kubectl(["label", "deploy", deploy_name,
             f"mining-coin={coin}", f"mining-group={group_name}", "--overwrite"])
    kubectl(["rollout", "restart", "deploy", deploy_name])
    log(f"Restarted {deploy_name} -> {coin}")


def main():
    log("=== Profit Switcher ===")
    log(f"Threshold: {SWITCH_THRESHOLD*100:.0f}% | Min hold: {MIN_HOLD_MINUTES}min")

    try:
        wtm = fetch_wtm()
        log(f"Fetched WhatToMine ({len(wtm)} coins)")
    except Exception as e:
        log(f"ERROR fetching WhatToMine: {e}")
        sys.exit(1)

    current = get_configmap()

    for group_name, group_cfg in GPU_GROUPS.items():
        profile_name = group_cfg["profile"]
        profile = GPU_PROFILES.get(profile_name, {})
        blacklist = set(group_cfg.get("coinBlacklist", []))
        deploys = group_cfg.get("deployments", [])

        if not deploys or not profile:
            continue

        revenues = {}
        for coin_ticker, wtm_name in WTM_NAMES.items():
            if coin_ticker in blacklist:
                continue
            coin_data = wtm.get(wtm_name)
            if not coin_data:
                continue
            algo = coin_data.get("algorithm", "").lower()
            # WhatToMine uses "Autolykos" not "autolykos2"
            if algo == "autolykos":
                algo = "autolykos2"
            our_hashrate = profile.get(algo, 0)
            if our_hashrate <= 0:
                continue
            rev = calc_revenue(coin_data, our_hashrate)
            if rev > 0:
                revenues[coin_ticker] = {"revenue": rev, "algo": algo, "coin": coin_ticker}

        if not revenues:
            log(f"[{group_name}] No profitable coins found")
            continue

        ranked = sorted(revenues.values(), key=lambda x: x["revenue"], reverse=True)
        best = ranked[0]
        best_coin = best["coin"]
        current_best = current.get(f"{group_name}-best", best_coin)

        log(f"[{group_name}] Best: {best_coin} ({best['revenue']:.10f} BTC/day, {best['algo']}) "
            f"| Current: {current_best}")

        for i, r in enumerate(ranked[:5]):
            marker = " <<<" if r["coin"] == current_best else ""
            log(f"  #{i+1} {r['coin']:5s} {r['revenue']:.10f} BTC/day ({r['algo']}){marker}")

        if best_coin == current_best:
            log(f"[{group_name}] No change")
            continue

        # Hysteresis check
        if current_best in revenues:
            current_rev = revenues[current_best]["revenue"]
            if current_rev > 0:
                improvement = (best["revenue"] - current_rev) / current_rev
                if improvement < SWITCH_THRESHOLD:
                    log(f"[{group_name}] Skipping: {best_coin} only "
                        f"{improvement*100:.1f}% better (need {SWITCH_THRESHOLD*100:.0f}%)")
                    continue

        # Minimum hold time check
        switch_time_str = current.get(f"{group_name}-switch-time", "")
        if switch_time_str and switch_time_str not in ("never", ""):
            try:
                switch_time = datetime.fromisoformat(switch_time_str)
                elapsed = (datetime.now(timezone.utc) - switch_time).total_seconds() / 60
                if elapsed < MIN_HOLD_MINUTES:
                    log(f"[{group_name}] Skipping: {elapsed:.0f}min since last switch "
                        f"(need {MIN_HOLD_MINUTES}min)")
                    continue
            except ValueError:
                pass

        # Switch
        if current_best in revenues and revenues[current_best]["revenue"] > 0:
            pct = (best["revenue"] / revenues[current_best]["revenue"] - 1) * 100
            log(f"[{group_name}] SWITCHING: {current_best} -> {best_coin} (+{pct:.1f}%)")
        else:
            log(f"[{group_name}] SWITCHING: {current_best} -> {best_coin}")

        update_configmap({
            f"{group_name}-best": best_coin,
            f"{group_name}-algo": best["algo"],
            f"{group_name}-revenue": f"{best['revenue']:.10f}",
            f"{group_name}-switch-time": datetime.now(timezone.utc).isoformat(),
            f"{group_name}-switch-from": current_best,
            "last-updated": datetime.now(timezone.utc).isoformat(),
        })

        for deploy in deploys:
            restart_deployment(deploy, best_coin, group_name)

    log("=== Done ===")


if __name__ == "__main__":
    main()
