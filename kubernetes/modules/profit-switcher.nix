{
  pkgs,
  config,
  lib,
  ...
}: let
  wallet = "krxXVNVMM7";

  # Our GPUs' actual hashrates per algorithm (in H/s)
  # These are real measured values from running miners
  gpuProfiles = {
    # NVIDIA RTX 4060 (forge-nvidia-0, forge-nvidia-1)
    rtx4060 = {
      kawpow = 16000000; # ~16 MH/s
      octopus = 16000000; # ~16 MH/s
      autolykos2 = 50000000; # ~50 MH/s
      nexapow = 200000000; # ~200 MH/s
      fishhash = 16000000; # ~16 MH/s
    };
    # NVIDIA RTX 3060 Ti (nexus)
    rtx3060ti = {
      kawpow = 20000000; # ~20 MH/s
      octopus = 20000000; # ~20 MH/s
      autolykos2 = 60000000; # ~60 MH/s
      nexapow = 250000000; # ~250 MH/s
      fishhash = 20000000; # ~20 MH/s
    };
    # NVIDIA RTX 3090 (zephyr-3090)
    rtx3090 = {
      kawpow = 50000000; # ~50 MH/s
      octopus = 80000000; # ~80 MH/s
      autolykos2 = 140000000; # ~140 MH/s
      nexapow = 600000000; # ~600 MH/s
      fishhash = 50000000; # ~50 MH/s
    };
    # AMD RX 5700 XT (forge-amd-0, forge-amd-1)
    rx5700xt = {
      kawpow = 22000000; # ~22 MH/s
      autolykos2 = 45000000; # ~45 MH/s
    };
  };

  # GPU groups: deployment name -> { profile, miner, deviceIndex }
  gpuGroups = {
    nvidia = {
      deployments = [
        "gpu-miner-forge-nvidia-0"
        "gpu-miner-forge-nvidia-1"
        "gpu-miner-nexus"
      ];
      profile = "rtx4060"; # simplified; forge=4060, nexus=3060ti
      miner = "rigel";
      minerBin = "rigel";
      coinBlacklist = [];
    };
    nvidia-3090 = {
      deployments = ["gpu-miner-zephyr"];
      profile = "rtx3090";
      miner = "rigel";
      minerBin = "rigel";
      coinBlacklist = [];
    };
    amd = {
      deployments = [
        "gpu-miner-forge-amd-0"
        "gpu-miner-forge-amd-1"
      ];
      profile = "rx5700xt";
      miner = "teamredminer";
      minerBin = "teamredminer";
      coinBlacklist = ["cfx" "nexa" "iron" "xel"];
    };
  };

  # Kryptex pool endpoints per coin
  kryptexPools = {
    rvn = {
      host = "rvn-us.kryptex.network";
      port = 7031;
      tlsPort = 8031;
      algo = "kawpow";
      coinFlag = "--coin rvn";
      walletFmt = "${wallet}";
    };
    cfx = {
      host = "cfx-us.kryptex.network";
      port = 7027;
      tlsPort = 8027;
      algo = "octopus";
      coinFlag = "--coin cfx";
      walletFmt = "${wallet}";
    };
    erg = {
      host = "erg-us.kryptex.network";
      port = 7021;
      tlsPort = null;
      algo = "autolykos2";
      coinFlag = "";
      walletFmt = "${wallet}";
    };
    nexa = {
      host = "nexa-us.kryptex.network";
      port = 7026;
      tlsPort = null;
      algo = "nexapow";
      coinFlag = "";
      walletFmt = "${wallet}";
    };
    xna = {
      host = "xna-us.kryptex.network";
      port = 7024;
      tlsPort = null;
      algo = "kawpow";
      coinFlag = "--coin xna";
      walletFmt = "${wallet}";
    };
    iron = {
      host = "iron-us.kryptex.network";
      port = 7050;
      tlsPort = null;
      algo = "fishhash";
      coinFlag = "";
      walletFmt = "${wallet}";
    };
    xel = {
      host = "xel-us.kryptex.network";
      port = 7055;
      tlsPort = null;
      algo = "xelishashv3";
      coinFlag = "";
      walletFmt = "${wallet}";
    };
  };

  # WhatToMine coin name mapping
  wtmNames = {
    rvn = "Ravencoin";
    cfx = "Conflux";
    erg = "Ergo";
    nexa = "Nexa";
    xna = "Neoxa";
    iron = "IronFish";
    xel = "Xelis";
  };

  profitSwitcherScript = pkgs.writePythonApplication "profit-switcher" {
    libraries = [pkgs.python312Packages.requests];
  } (builtins.readFile ./profit-switcher.py);
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects = {
    # --- ConfigMap: current profit switching state ---
    mining.ConfigMap.mining-profit-config = {
      data = {
        nvidia-best = "rvn";
        nvidia-3090-best = "cfx";
        amd-best = "rvn";
        last-updated = "never";
      };
    };

    # --- RBAC for profit switcher ---
    mining.ServiceAccount.profit-switcher = {};
    mining.Role.profit-switcher-role = {
      rules = [
        {
          apiGroups = [""];
          resources = ["configmaps"];
          verbs = ["get" "update" "patch"];
          resourceNames = ["mining-profit-config"];
        }
        {
          apiGroups = ["apps"];
          resources = ["deployments"];
          verbs = ["get" "list" "patch"];
        }
      ];
    };
    mining.RoleBinding.profit-switcher-binding = {
      subjects = [
        {
          kind = "ServiceAccount";
          name = "profit-switcher";
          namespace = "mining";
        }
      ];
      roleRef = {
        kind = "Role";
        name = "profit-switcher-role";
        apiGroup = "rbac.authorization.k8s.io";
      };
    };

    # --- CronJob: profit switcher ---
    mining.CronJob.profit-switcher = {
      metadata.labels = managed // {
        app = "profit-switcher";
        workload = "mining-infra";
      };
      spec = {
        schedule = "*/5 * * * *";
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 3;
        jobTemplate = {
          spec = {
            template = {
              spec = {
                nodeName = "nexus";
                serviceAccountName = "profit-switcher";
                automountServiceAccountToken = true;
                restartPolicy = "OnFailure";
                containers = {
                  _namedlist = true;
                  switcher = {
                    image = "python:3.12-slim";
                    command = ["python" "/opt/profit-switcher.py"];
                    env = {
                      _namedlist = true;
                      KUBECONFIG = {
                        name = "KUBECONFIG";
                        value = "/etc/rancher/k3s/k3s.yaml";
                      };
                      GPU_PROFILES = {
                        name = "GPU_PROFILES";
                        value = builtins.toJSON gpuProfiles;
                      };
                      KRYPTXEX_POOLS = {
                        name = "KRYPTXEX_POOLS";
                        value = builtins.toJSON kryptexPools;
                      };
                      GPU_GROUPS = {
                        name = "GPU_GROUPS";
                        value = builtins.toJSON gpuGroups;
                      };
                      WTM_NAMES = {
                        name = "WTM_NAMES";
                        value = builtins.toJSON wtmNames;
                      };
                      WALLET = {
                        name = "WALLET";
                        value = wallet;
                      };
                      SWITCH_THRESHOLD = {
                        name = "SWITCH_THRESHOLD";
                        value = "0.10";
                      };
                      MIN_HOLD_MINUTES = {
                        name = "MIN_HOLD_MINUTES";
                        value = "30";
                      };
                    };
                    resources = {
                      requests = {
                        cpu = "50m";
                        memory = "64Mi";
                      };
                      limits = {
                        cpu = "200m";
                        memory = "128Mi";
                      };
                    };
                    volumeMounts = {
                      _namedlist = true;
                      script = {
                        mountPath = "/opt/profit-switcher.py";
                        subPath = "profit-switcher.py";
                      };
                      kubeconfig = {
                        mountPath = "/etc/rancher/k3s/k3s.yaml";
                        readOnly = true;
                      };
                    };
                  };
                };
                volumes = {
                  _namedlist = true;
                  script.configMap.name = "profit-switcher-script";
                  kubeconfig.hostPath.path = "/etc/rancher/k3s/k3s.yaml";
                };
              };
            };
          };
        };
      };
    };

    # --- ConfigMap: the switcher script itself ---
    mining.ConfigMap.profit-switcher-script = {
      data."profit-switcher.py" = ''
        #!/usr/bin/env python3
        """Profit switcher for Kryptex auto-exchange pools.
        Polls WhatToMine API, calculates revenue per GPU group,
        and patches mining deployments to mine the most profitable coin.
        """
        import json, os, sys, time, subprocess, math, requests
        from datetime import datetime, timezone, timedelta

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
            """Fetch WhatToMine coins.json and return parsed data."""
            r = requests.get("https://whattomine.com/coins.json", timeout=30)
            r.raise_for_status()
            return r.json()["coins"]

        def calc_revenue(coin_data, our_hashrate_hs):
            """Calculate BTC/day revenue for our hashrate.
            revenue = (our_hashrate / nethash) * block_reward * (86400 / block_time) * exchange_rate
            """
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

        def update_configmap(data):
            """Patch the configmap with new data."""
            patches = []
            for k, v in data.items():
                patches.append({"op": "replace", "path": f"/data/{k}", "value": v})
            patch_json = json.dumps(patches)
            result = kubectl(["patch", "configmap", CONFIGMAP, "--type=json", "-p", patch_json])
            if result:
                log(f"ConfigMap updated: {data}")
            return result

        def get_deployment(deploy_name):
            out = kubectl(["get", "deploy", deploy_name, "-o", "json"])
            if not out:
                return None
            return json.loads(out)

        def get_deployment_coin(deploy_name):
            """Extract current coin from deployment labels."""
            d = get_deployment(deploy_name)
            if not d:
                return None
            return d.get("metadata", {}).get("labels", {}).get("mining-coin")

        def set_deployment_coin(deploy_name, coin, group_name):
            """Patch deployment with new coin config."""
            pool = KRYPTXEX_POOLS.get(coin)
            if not pool:
                log(f"No pool config for {coin}")
                return False

            # Update label
            kubectl(["label", "deploy", deploy_name,
                     f"mining-coin={coin}", "mining-group={group_name}",
                     "--overwrite"])

            # Restart the deployment - the pod wrapper will read the ConfigMap
            # and start the correct miner with the correct args
            kubectl(["rollout", "restart", "deploy", deploy_name])
            log(f"Restarted {deploy_name} for {coin}")
            return True

        def main():
            log("=== Profit Switcher Starting ===")
            log(f"Threshold: {SWITCH_THRESHOLD*100:.0f}% | Min hold: {MIN_HOLD_MINUTES}min")

            # 1. Fetch WhatToMine data
            try:
                wtm = fetch_wtm()
                log(f"Fetched WhatToMine data ({len(wtm)} coins)")
            except Exception as e:
                log(f"ERROR fetching WhatToMine: {e}")
                sys.exit(1)

            # 2. Get current state
            current = get_configmap()
            last_updated = current.get("last-updated", "never")

            # 3. For each GPU group, find best coin
            for group_name, group_cfg in GPU_GROUPS.items():
                profile_name = group_cfg["profile"]
                profile = GPU_PROFILES.get(profile_name, {})
                blacklist = set(group_cfg.get("coinBlacklist", []))
                deploys = group_cfg.get("deployments", [])

                if not deploys:
                    continue

                # Calculate revenue for each supported coin
                revenues = {}
                for coin_ticker, wtm_name in WTM_NAMES.items():
                    if coin_ticker in blacklist:
                        continue

                    coin_data = wtm.get(wtm_name)
                    if not coin_data:
                        continue

                    algo = coin_data.get("algorithm", "").lower()
                    our_hashrate = profile.get(algo, 0)
                    if our_hashrate <= 0:
                        continue

                    rev = calc_revenue(coin_data, our_hashrate)
                    if rev > 0:
                        revenues[coin_ticker] = {
                            "revenue": rev,
                            "algo": algo,
                            "coin": coin_ticker,
                        }

                if not revenues:
                    log(f"[{group_name}] No profitable coins found")
                    continue

                # Sort by revenue
                ranked = sorted(revenues.values(), key=lambda x: x["revenue"], reverse=True)
                best = ranked[0]
                best_coin = best["coin"]

                # Get current best for this group
                current_best = current.get(f"{group_name}-best", best_coin)

                log(f"[{group_name}] Best: {best_coin} ({best['revenue']:.8f} BTC/day, {best['algo']}) "
                    f"| Current: {current_best}")

                # Log all options
                for i, r in enumerate(ranked[:5]):
                    marker = " <<<" if r["coin"] == current_best else ""
                    log(f"  #{i+1} {r['coin']:5s} {r['revenue']:.8f} BTC/day ({r['algo']}){marker}")

                # Apply hysteresis
                if best_coin == current_best:
                    log(f"[{group_name}] No change needed")
                    continue

                if current_best in revenues:
                    current_rev = revenues[current_best]["revenue"]
                    improvement = (best["revenue"] - current_rev) / current_rev if current_rev > 0 else 1.0
                    if improvement < SWITCH_THRESHOLD:
                        log(f"[{group_name}] Skipping switch: {best_coin} only "
                            f"{improvement*100:.1f}% better (threshold: {SWITCH_THRESHOLD*100:.0f}%)")
                        continue

                # Check minimum hold time
                switch_time_str = current.get(f"{group_name}-switch-time", "")
                if switch_time_str and switch_time_str != "never":
                    try:
                        switch_time = datetime.fromisoformat(switch_time_str)
                        elapsed = (datetime.now(timezone.utc) - switch_time).total_seconds() / 60
                        if elapsed < MIN_HOLD_MINUTES:
                            log(f"[{group_name}] Skipping: only {elapsed:.0f}min since last switch "
                                f"(min: {MIN_HOLD_MINUTES}min)")
                            continue
                    except ValueError:
                        pass

                # Switch!
                log(f"[{group_name}] SWITCHING: {current_best} -> {best_coin} "
                    f"(+{(best['revenue']/max(revenues.get(current_best, {}).get('revenue', 1e-30))-1)*100:.1f}%)")

                update_configmap({
                    f"{group_name}-best": best_coin,
                    f"{group_name}-algo": best["algo"],
                    f"{group_name}-revenue": f"{best['revenue']:.10f}",
                    f"{group_name}-switch-time": datetime.now(timezone.utc).isoformat(),
                    f"{group_name}-switch-from": current_best,
                    "last-updated": datetime.now(timezone.utc).isoformat(),
                })

                # Restart deployments
                for deploy in deploys:
                    set_deployment_coin(deploy, best_coin, group_name)

            log("=== Profit Switcher Complete ===")

        if __name__ == "__main__":
            main()
      '';
    };
  };
}
