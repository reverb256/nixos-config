# Mining Deployment Configurations — CSI Migration Reference

## Files Retrieved

1. `kubernetes-manifests/mining/gpu-miner-forge-amd-0.yaml` (full) — AMD GPU 0 lolMiner
2. `kubernetes-manifests/mining/gpu-miner-forge-amd-1.yaml` (full) — AMD GPU 1 lolMiner
3. `kubernetes-manifests/mining/gpu-miner-forge-nvidia-0.yaml` (full) — NVIDIA GPU 0 lolMiner
4. `kubernetes-manifests/mining/gpu-miner-forge-nvidia-1.yaml` (full) — NVIDIA GPU 1 lolMiner
5. `kubernetes-manifests/mining/gpu-miner-nexus.yaml` (full) — Nexus RTX 3060 Ti lolMiner
6. `kubernetes-manifests/mining/gpu-miner-zephyr.yaml` (full) — Zephyr RTX 3090 lolMiner
7. `kubernetes-manifests/mining/xmrig-nexus.yaml` (full) — Nexus CPU xmrig (base)
8. `kubernetes-manifests/mining/xmrig-nexus-variable.yaml` (full) — Nexus CPU xmrig (variable/preemptible)
9. `kubernetes-manifests/mining/xmrig-sentry.yaml` (full) — Sentry CPU xmrig (base)
10. `kubernetes-manifests/mining/xmrig-sentry-variable.yaml` (full) — Sentry CPU xmrig (variable/preemptible)
11. `kubernetes-manifests/mining/xmrig-zephyr.yaml` (full) — Zephyr CPU xmrig (base)
12. `kubernetes-manifests/mining/xmrig-zephyr-variable.yaml` (full) — Zephyr CPU xmrig (variable/preemptible)
13. `kubernetes-manifests/mining/xmrig-proxy-deployment.yaml` (full) — Stratum proxy
14. `kubernetes-manifests/mining/xmrig-proxy-configmap.yaml` (full) — Proxy config

---

## Architecture Overview

### Mining Topology

```
                    ┌─────────────────────┐
                    │  xmrig-proxy (nexus) │  ← Stratum proxy on nexus:3333
                    │  priority: system-   │     API on nexus:8081
                    │  cluster-critical     │
                    └──────┬────────────────┘
                           │
              ┌────────────┼────────────────────────────┐
              │            │                             │
         CPU miners    GPU miners (direct connect)    GPU miners (direct connect)
         via proxy     to kryptex CR29 pools          to kryptex CR29 pools
              │            │                             │
     ┌────────┼────┐   ┌───┼───────┐              ┌─────┼──────┐
     │        │    │   │   │       │              │     │      │
  zephyr  nexus sentry forge-amd forge-nvidia    zephyr nexus
  8thr   6thr  4thr  GPU0 GPU1  GPU0  GPU1      GPU1   GPU0
  (+8var) (+6var)(+4var) RX5700XT RTX3060Ti     RTX3090 RTX3060Ti
                        x2     x1      x1
```

### Two Connection Modes

1. **CPU miners** → `xmrig-proxy` (nexus:3333) → kryptex RandomX pools (via proxy)
2. **GPU miners** → kryptex CR29 pools **directly** (dual-pool failover: US primary, EU secondary)

### Three Deployment Categories

| Category | Count | Priority | Image Strategy |
|----------|-------|----------|----------------|
| GPU lolMiner (direct pool) | 6 | `mining-low` | AMD: `ubuntu:24.04` + host nix-store mount; NVIDIA: `swamp7/lolminer` + host nix-store mount |
| CPU xmrig base | 3 | `mining-low` | `xmrig-alpine:6.25.0` (local, `imagePullPolicy: Never`) |
| CPU xmrig variable | 3 | `preemptible-mining` | `xmrig-alpine:6.25.0` (local, `imagePullPolicy: Never`) |
| xmrig-proxy | 1 | `system-cluster-critical` | `xmrig-proxy:nixos-6.24.0` (local, `imagePullPolicy: Never`) |

---

## Deployment Details

### 1. gpu-miner-forge-amd-0

| Field | Value |
|-------|-------|
| **Image** | `docker.io/library/ubuntu:24.04` |
| **Command** | `/nix/store/mpkgc1sk57hmb62qj3dahvmnjag1l3mc-lolminer-1.98a/bin/lolMiner` |
| **Args** | `--algo=CR29 --pool=xtm-c29-us.kryptex.network:8040 --user=krxXVNVMM7.forge-a0 --pass=x --tls=1 --pool=xtm-c29-eu.kryptex.network:8040 --user=krxXVNVMM7.forge-a0 --pass=x --tls=1 --devices=0 --apiport=4070` |
| **Env** | `LD_LIBRARY_PATH=/run/opengl-driver/lib` <br> `OCL_ICD_VENDORS=/etc/OpenCL/vendors/` |
| **Port** | 4070/tcp (api) |
| **nodeName** | `forge` |
| **hostNetwork** | `true` |
| **serviceAccountName** | `gpu-miner-sa` |
| **priorityClassName** | `mining-low` |
| **Strategy** | `Recreate` |
| **securityContext** | `privileged: true` |
| **Resources req** | `memory: 512Mi, cpu: 500m` |
| **Resources lim** | `cpu: 2` (no memory limit — /nix/store mount causes cgroup OOM) |
| **Tolerations** | none |
| **Probes** | liveness/readiness: `exec pgrep -f lolMiner` (live: 30s/30s, ready: 10s/10s) |

**Volume Mounts:**

| Name | MountPath | Source | Mode |
|------|-----------|--------|------|
| dri | `/dev/dri` | hostPath `/dev/dri` | rw |
| kfd | `/dev/kfd` | hostPath `/dev/kfd` | rw |
| nix-store | `/nix/store` | hostPath `/nix/store` | ro |
| opengl-driver | `/run/opengl-driver/lib` | hostPath `/run/opengl-driver/lib` | ro |
| opencl-icd | `/etc/OpenCL/vendors` | hostPath `/nix/store/6yvx83sa6iwhr6xnjjlfjg56jnki5mdn-clr-7.2.0-icd/etc/OpenCL/vendors` (Directory) | ro |

---

### 2. gpu-miner-forge-amd-1

| Field | Value |
|-------|-------|
| **Image** | `docker.io/library/ubuntu:24.04` |
| **Command** | `/nix/store/mpkgc1sk57hmb62qj3dahvmnjag1l3mc-lolminer-1.98a/bin/lolMiner` |
| **Args** | `--algo=CR29 --pool=xtm-c29-us.kryptex.network:8040 --user=krxXVNVMM7.forge-a1 --pass=x --tls=1 --pool=xtm-c29-eu.kryptex.network:8040 --user=krxXVNVMM7.forge-a1 --pass=x --tls=1 --devices=1 --apiport=4071` |
| **Env** | `LD_LIBRARY_PATH=/run/opengl-driver/lib` <br> `OCL_ICD_VENDORS=/etc/OpenCL/vendors/` |
| **Port** | 4071/tcp (api) |
| **nodeName** | `forge` |
| **hostNetwork** | `true` |
| **serviceAccountName** | `gpu-miner-sa` |
| **priorityClassName** | `mining-low` |
| **Strategy** | `Recreate` |
| **securityContext** | `privileged: true` |
| **Resources req** | `memory: 512Mi, cpu: 500m` |
| **Resources lim** | `cpu: 2` (no memory limit) |
| **Tolerations** | none |
| **Probes** | liveness/readiness: `exec pgrep -f lolMiner` (live: 30s/30s, ready: 10s/10s) |

**Volume Mounts:** Identical to amd-0 (same ICD path, same 5 volumes).

---

### 3. gpu-miner-forge-nvidia-0

| Field | Value |
|-------|-------|
| **Image** | `docker.io/swamp7/lolminer:latest` |
| **Command** | (default entrypoint) |
| **Args** | `--algo=CR29 --pool=xtm-c29-us.kryptex.network:8040 --user=krxXVNVMM7.forge-n0 --pass=x --tls=1 --pool=xtm-c29-eu.kryptex.network:8040 --user=krxXVNVMM7.forge-n0 --pass=x --tls=1 --devices=0 --cclk=2350 --moff=1100 --pl=90 --apiport=4068` |
| **Env** | `LD_LIBRARY_PATH=/run/opengl-driver/lib:/nix/store` |
| **Port** | 4068/tcp (api) |
| **nodeName** | `forge` |
| **hostNetwork** | `true` |
| **priorityClassName** | `mining-low` |
| **Strategy** | `RollingUpdate` (maxSurge: 0, maxUnavailable: 1) |
| **securityContext** | `privileged: true` |
| **Resources req** | `memory: 4Gi, cpu: 2, nvidia.com/gpu: 1, amd.com/gpu: 0` |
| **Resources lim** | `memory: 8Gi, cpu: 4, nvidia.com/gpu: 1, amd.com/gpu: 0` |
| **Tolerations** | none |
| **Probes** | none |
| **Pod labels** | `pod-security.kubernetes.io/enforce: privileged` |

**Volume Mounts:**

| Name | MountPath | Source | Mode |
|------|-----------|--------|------|
| nvidia | `/run/opengl-driver/lib` | hostPath `/run/opengl-driver/lib` | ro |
| dev | `/dev` | hostPath `/dev` | rw |
| nix-store | `/nix/store` | hostPath `/nix/store` | ro |

---

### 4. gpu-miner-forge-nvidia-1

| Field | Value |
|-------|-------|
| **Image** | `docker.io/swamp7/lolminer:latest` |
| **Command** | (default entrypoint) |
| **Args** | `--algo=CR29 --pool=xtm-c29-us.kryptex.network:8040 --user=krxXVNVMM7.forge-n1 --pass=x --tls=1 --pool=xtm-c29-eu.kryptex.network:8040 --user=krxXVNVMM7.forge-n1 --pass=x --tls=1 --devices=1 --cclk=2350 --moff=1100 --pl=90 --apiport=4069` |
| **Env** | `LD_LIBRARY_PATH=/run/opengl-driver/lib:/nix/store` |
| **Port** | 4069/tcp (api) |
| **nodeName** | `forge` |
| **hostNetwork** | `true` |
| **priorityClassName** | `mining-low` |
| **Strategy** | `RollingUpdate` (maxSurge: 0, maxUnavailable: 1) |
| **securityContext** | `privileged: true` |
| **Resources req** | `memory: 4Gi, cpu: 2, nvidia.com/gpu: 1, amd.com/gpu: 0` |
| **Resources lim** | `memory: 8Gi, cpu: 4, nvidia.com/gpu: 1, amd.com/gpu: 0` |
| **Tolerations** | none |
| **Probes** | none |

**Volume Mounts:** Identical to forge-nvidia-0.

---

### 5. gpu-miner-nexus

| Field | Value |
|-------|-------|
| **Image** | `docker.io/swamp7/lolminer:latest` |
| **Command** | (default entrypoint) |
| **Args** | `--algo=CR29 --pool=xtm-c29-us.kryptex.network:8040 --user=krxXVNVMM7.nexus-gpu --pass=x --tls=1 --pool=xtm-c29-eu.kryptex.network:8040 --user=krxXVNVMM7.nexus-gpu --pass=x --tls=1 --devices=0 --cclk=1605 --moff=1500 --pl=120 --apiport=4068` |
| **Env** | `LD_LIBRARY_PATH=/run/opengl-driver/lib:/nix/store` |
| **Port** | 4068/tcp (api) |
| **nodeName** | `nexus` |
| **hostNetwork** | `true` |
| **serviceAccountName** | `gpu-miner-sa` |
| **automountServiceAccountToken** | `false` |
| **priorityClassName** | `mining-low` |
| **Strategy** | `Recreate` |
| **securityContext** | `privileged: true` |
| **Resources req** | `memory: 4Gi, cpu: 2, nvidia.com/gpu: 1` |
| **Resources lim** | `memory: 8Gi, cpu: 4, nvidia.com/gpu: 1` |
| **Tolerations** | `node-role.kubernetes.io/control-plane:NoSchedule` |
| **Probes** | none |

**Volume Mounts:** Same as forge-nvidia (nvidia + dev + nix-store).

---

### 6. gpu-miner-zephyr

| Field | Value |
|-------|-------|
| **Image** | `docker.io/swamp7/lolminer:latest` |
| **Command** | (default entrypoint) |
| **Args** | `--algo=CR29 --pool=xtm-c29-us.kryptex.network:8040 --user=krxXVNVMM7.zephyr-gpu --pass=x --tls=1 --pool=xtm-c29-eu.kryptex.network:8040 --user=krxXVNVMM7.zephyr-gpu --pass=x --tls=1 --devices=1 --pl=250 --apiport=4068` |
| **Env** | `LD_LIBRARY_PATH=/run/opengl-driver/lib:/nix/store` |
| **Port** | 4068/tcp (api) |
| **nodeName** | `zephyr` |
| **hostNetwork** | `true` |
| **serviceAccountName** | `gpu-miner-sa` |
| **automountServiceAccountToken** | `false` |
| **priorityClassName** | `mining-low` |
| **Strategy** | `Recreate` |
| **securityContext** | `privileged: true, capabilities: {add: [SYS_ADMIN]}` |
| **Resources req** | `memory: 4Gi, cpu: 2, nvidia.com/gpu: 1` |
| **Resources lim** | `memory: 8Gi, cpu: 4, nvidia.com/gpu: 1` |
| **Pod labels** | `pod-security.kubernetes.io/enforce: privileged` |
| **Annotations** | `prometheus.io/scrape: "true"`, `prometheus.io/port: "4068"` |
| **Probes** | liveness: `httpGet /:4068` (30s/30s, fail 3) <br> readiness: `httpGet /:4068` (60s/15s, fail 10) |

**Tolerations:**

| Key | Operator | Value | Effect |
|-----|----------|-------|--------|
| `node-role.kubernetes.io/control-plane` | Exists | — | NoSchedule |
| `workstation` | Equal | `true` | NoSchedule |
| `interactive` | Equal | `true` | NoExecute |
| `ram-constrained` | Equal | `true` | NoSchedule |

**Volume Mounts:** Same as forge-nvidia (nvidia + dev + nix-store).

---

### 7. xmrig-nexus

| Field | Value |
|-------|-------|
| **Image** | `xmrig-alpine:6.25.0` (`imagePullPolicy: Never`) |
| **Command** | (default entrypoint) |
| **Args** | `-o 10.1.1.120:3333 -u nexus-cpu --tls=false --threads=6 --donate-level=1 --http-enabled --http-host=0.0.0.0 --http-port=8082` |
| **Env** | `XMRIG_NO_TLS=1` |
| **Port** | 8082/tcp (api) |
| **nodeName** | `nexus` |
| **hostNetwork** | `true` |
| **hostIPC** | `true` |
| **dnsPolicy** | `ClusterFirstWithHostNet` |
| **serviceAccountName** | `gpu-miner-sa` |
| **automountServiceAccountToken** | `false` |
| **priorityClassName** | `mining-low` |
| **Strategy** | `Recreate` |
| **securityContext** | `privileged: true` |
| **Resources req** | `memory: 1Gi, cpu: 3` |
| **Resources lim** | `memory: 3Gi, cpu: 6` |
| **Annotations** | `prometheus.io/scrape: "true"`, `prometheus.io/port: "8082"`, `prometheus.io/path: "/1/summary"` |
| **Probes** | liveness/readiness: `httpGet /1/summary:8082` (live: 30s/30s fail 3, ready: 10s/10s fail 3) |

**Tolerations:**

| Key | Operator | Value | Effect |
|-----|----------|-------|--------|
| `node-role.kubernetes.io/control-plane` | Exists | — | NoSchedule |

**Volume Mounts:**

| Name | MountPath | Source | Propagation |
|------|-----------|--------|-------------|
| msr | `/dev/cpu` | hostPath `/dev/cpu` (Directory) | HostToContainer |
| hugepages | `/dev/hugepages` | hostPath `/dev/hugepages` (Directory) | HostToContainer |
| sys-module-msr | `/sys/module/msr` | hostPath `/sys/module/msr` (Directory) | HostToContainer |
| tmp | `/tmp` | emptyDir | — |

---

### 8. xmrig-nexus-variable

| Field | Value |
|-------|-------|
| **Image** | `docker.io/library/xmrig-alpine:6.25.0` (`imagePullPolicy: Never`) |
| **Command** | (default entrypoint) |
| **Args** | `-o 10.1.1.120:3333 -u nexus-cpu-var --tls=false --threads=6 --donate-level=1 --http-enabled --http-host=0.0.0.0 --http-port=8083` |
| **Env** | none |
| **Port** | none defined |
| **nodeName** | `nexus` |
| **hostNetwork** | `true` |
| **hostIPC** | `true` |
| **hostPID** | `true` |
| **dnsPolicy** | `ClusterFirstWithHostNet` |
| **serviceAccountName** | `gpu-miner-sa` |
| **automountServiceAccountToken** | `false` |
| **priorityClassName** | `preemptible-mining` |
| **Strategy** | `Recreate` |
| **securityContext** | `privileged: true` |
| **Resources req** | `memory: 2Gi, cpu: 3` |
| **Resources lim** | `memory: 3Gi, cpu: 6` |
| **Tolerations** | `node-role.kubernetes.io/control-plane:NoSchedule` |
| **Probes** | none |

**Volume Mounts:** Same as xmrig-nexus (msr + hugepages + sys-module-msr + tmp).

---

### 9. xmrig-sentry

| Field | Value |
|-------|-------|
| **Image** | `xmrig-alpine:6.25.0` (`imagePullPolicy: Never`) |
| **Command** | (default entrypoint) |
| **Args** | `-o 10.1.1.120:3333 -u sentry-cpu --tls=false --threads=4 --donate-level=1 --http-enabled --http-host=0.0.0.0 --http-port=8081` |
| **Env** | `XMRIG_NO_TLS=1` |
| **Port** | 8081/tcp (api) |
| **nodeName** | `sentry` |
| **hostNetwork** | `true` |
| **hostIPC** | `true` |
| **dnsPolicy** | `ClusterFirstWithHostNet` |
| **serviceAccountName** | `gpu-miner-sa` |
| **automountServiceAccountToken** | `false` |
| **priorityClassName** | `mining-low` |
| **Strategy** | `Recreate` |
| **securityContext** | `privileged: true` |
| **Resources req** | `memory: 512Mi, cpu: 1` |
| **Resources lim** | `memory: 4Gi, cpu: 4` |
| **Annotations** | `prometheus.io/scrape: "true"`, `prometheus.io/port: "8081"`, `prometheus.io/path: "/1/summary"` |
| **Probes** | liveness/readiness: `httpGet /1/summary:8081` (live: 30s/30s fail 3, ready: 10s/10s fail 3) |

**Tolerations:** `node-role.kubernetes.io/control-plane:NoSchedule`

**Volume Mounts:** Same pattern (msr + hugepages + sys-module-msr + tmp).

---

### 10. xmrig-sentry-variable

| Field | Value |
|-------|-------|
| **Image** | `docker.io/library/xmrig-alpine:6.25.0` (`imagePullPolicy: Never`) |
| **Command** | (default entrypoint) |
| **Args** | `-o 10.1.1.120:3333 -u sentry-cpu-var --tls=false --threads=4 --donate-level=1 --http-enabled --http-host=0.0.0.0 --http-port=8083` |
| **Env** | none |
| **Port** | none defined |
| **nodeName** | `sentry` |
| **hostNetwork** | `true` |
| **hostIPC** | `true` |
| **hostPID** | `true` |
| **dnsPolicy** | `ClusterFirstWithHostNet` |
| **serviceAccountName** | `gpu-miner-sa` |
| **automountServiceAccountToken** | `false` |
| **priorityClassName** | `preemptible-mining` |
| **Strategy** | `Recreate` |
| **securityContext** | `privileged: true` |
| **Resources req** | `memory: 1Gi, cpu: 2` |
| **Resources lim** | `memory: 3Gi, cpu: 4` |
| **Tolerations** | `node-role.kubernetes.io/control-plane:NoSchedule` |
| **Probes** | none |

**Volume Mounts:** Same pattern (msr + hugepages + sys-module-msr + tmp).

---

### 11. xmrig-zephyr

| Field | Value |
|-------|-------|
| **Image** | `xmrig-alpine:6.25.0` (`imagePullPolicy: Never`) |
| **Command** | `/bin/sh -c "exec /bin/xmrig -o 10.1.1.120:3333 -u zephyr-cpu --threads=8 --donate-level=1 --api-worker-id=zephyr-cpu --http-enabled --http-host=0.0.0.0 --http-port=8082"` |
| **Args** | (inline via command) |
| **Env** | `XMRIG_NO_TLS=1` |
| **Port** | 8082/tcp (api) |
| **nodeName** | `zephyr` |
| **hostNetwork** | `true` |
| **hostIPC** | `true` |
| **hostPID** | `true` |
| **dnsPolicy** | `ClusterFirstWithHostNet` |
| **serviceAccountName** | `gpu-miner-sa` |
| **automountServiceAccountToken** | `false` |
| **priorityClassName** | `mining-low` |
| **Strategy** | `Recreate` |
| **terminationGracePeriodSeconds** | 30 |
| **securityContext** | `privileged: true` |
| **Resources req** | `memory: 1Gi, cpu: 4` |
| **Resources lim** | `memory: 4Gi, cpu: 8` |
| **Annotations** | `prometheus.io/scrape: "true"`, `prometheus.io/port: "8082"`, `prometheus.io/path: "/1/summary"` |
| **Probes** | liveness/readiness: `httpGet /1/summary:8082` (live: 30s/30s fail 3, ready: 10s/10s fail 3) |

**Tolerations:**

| Key | Operator | Value | Effect |
|-----|----------|-------|--------|
| `node-role.kubernetes.io/control-plane` | Exists | — | NoSchedule |
| `workstation` | Equal | `true` | NoSchedule |
| `interactive` | Equal | `true` | NoExecute |
| `ram-constrained` | Equal | `true` | NoSchedule |

**Volume Mounts:** Same pattern (msr + hugepages + sys-module-msr + tmp).

---

### 12. xmrig-zephyr-variable

| Field | Value |
|-------|-------|
| **Image** | `docker.io/library/xmrig-alpine:6.25.0` (`imagePullPolicy: Never`) |
| **Command** | (default entrypoint) |
| **Args** | `-o 10.1.1.110:3333 -u zephyr-cpu-var --tls=false --threads=8 --donate-level=1 --http-enabled --http-host=0.0.0.0 --http-port=8083` |
| **Env** | none |
| **Port** | none defined |
| **nodeName** | `zephyr` |
| **hostNetwork** | `true` |
| **hostIPC** | `true` |
| **hostPID** | `true` |
| **dnsPolicy** | `ClusterFirstWithHostNet` |
| **serviceAccountName** | `gpu-miner-sa` |
| **automountServiceAccountToken** | `false` |
| **priorityClassName** | `preemptible-mining` |
| **Strategy** | `Recreate` |
| **securityContext** | `privileged: true` |
| **Resources req** | `memory: 2Gi, cpu: 4` |
| **Resources lim** | `memory: 4Gi, cpu: 8` |
| **Tolerations** | Same 4 as xmrig-zephyr (control-plane, workstation, interactive, ram-constrained) |
| **Probes** | none |

**Volume Mounts:** Same pattern (msr + hugepages + sys-module-msr + tmp).

> ⚠️ **NOTE:** xmrig-zephyr-variable connects to `10.1.1.110:3333` (ZEPHYR's own proxy port?) instead of `10.1.1.120:3333` (nexus). This may be intentional or a bug.

---

### 13. xmrig-proxy

| Field | Value |
|-------|-------|
| **Image** | `xmrig-proxy:nixos-6.24.0` (`imagePullPolicy: Never`) |
| **Command** | (default entrypoint) |
| **Args** | `--config=/etc/xmrig-proxy/config.json --no-color` |
| **Env** | none |
| **Ports** | 3333/tcp (stratum), 8081/tcp (api) |
| **nodeName** | `nexus` |
| **hostNetwork** | `true` |
| **serviceAccountName** | `gpu-miner-sa` |
| **automountServiceAccountToken** | `false` |
| **priorityClassName** | `system-cluster-critical` |
| **Strategy** | `RollingUpdate` (maxSurge: 0, maxUnavailable: 1) |
| **securityContext** | `allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}` |
| **Resources req** | `memory: 128Mi, cpu: 100m` |
| **Resources lim** | `memory: 1Gi, cpu: 1000m` |
| **Annotations** | `prometheus.io/scrape: "true"`, `prometheus.io/port: "8081"` |
| **Probes** | liveness/readiness: `tcpSocket :3333` (live: 15s/20s fail 3, ready: 5s/10s fail 3) |

**Tolerations:** `node-role.kubernetes.io/control-plane:NoSchedule`

**Volume Mounts:**

| Name | MountPath | Source | Mode |
|------|-----------|--------|------|
| config | `/etc/xmrig-proxy` | configMap `xmrig-proxy-config` | ro |
| secrets | `/etc/xmrig-proxy-secrets` | secret `xmrig-proxy-secret` (keys: `api-token`→`api-token`, `kryptex-password`→`pool-password`) | ro |

---

### 14. xmrig-proxy-configmap

**ConfigMap name:** `xmrig-proxy-config` (namespace: `mining`)

**config.json contents:**

```json
{
  "bind": [{"host": "0.0.0.0", "port": 3333}],
  "api": {
    "port": 8081,
    "restricted": true,
    "token-file": "/etc/xmrig-proxy-secrets/api-token"
  },
  "randomx": {"mode": "light"},
  "log": {"level": 5},
  "pools": [
    {
      "id": "kryptex-rx-us",
      "url": "xtm-rx-us.kryptex.network:8038",
      "user": "krxXVNVMM7.cpu-proxy",
      "pass-file": "/etc/xmrig-proxy-secrets/pool-password",
      "tls": true, "keepalive": true, "priority": 1
    },
    {
      "id": "kryptex-rx-eu",
      "url": "xtm-rx-eu.kryptex.network:8038",
      "user": "krxXVNVMM7.cpu-proxy",
      "pass-file": "/etc/xmrig-proxy-secrets/pool-password",
      "tls": true, "keepalive": true, "priority": 2
    },
    {
      "id": "kryptex-cr29-us",
      "url": "xtm-c29-us.kryptex.network:8040",
      "user": "krxXVNVMM7.gpu-proxy",
      "pass-file": "/etc/xmrig-proxy-secrets/pool-password",
      "tls": true, "keepalive": true, "priority": 1
    },
    {
      "id": "kryptex-cr29-eu",
      "url": "xtm-c29-eu.kryptex.network:8040",
      "user": "krxXVNVMM7.gpu-proxy",
      "pass-file": "/etc/xmrig-proxy-secrets/pool-password",
      "tls": true, "keepalive": true, "priority": 2
    }
  ],
  "workers": [
    {"id": "zephyr-cpu", "password-file": "..."},
    {"id": "nexus-cpu", "password-file": "..."},
    {"id": "sentry-cpu", "password-file": "..."},
    {"id": "zephyr-gpu", "password-file": "..."},
    {"id": "nexus-gpu", "password-file": "..."},
    {"id": "forge-gpu", "password-file": "..."},
    {"id": "forge-gpu-nvidia", "password-file": "..."},
    {"id": "forge-gpu-amd", "password-file": "..."}
  ]
}
```

---

## CSI Migration Concerns

### Volume Patterns to Replace

| Current Pattern | Used By | CSI Target |
|----------------|---------|------------|
| `hostPath /nix/store` (ro) | All GPU miners, forge-nvidia | Mount individual nix store paths as CSI volumes |
| `hostPath /run/opengl-driver/lib` (ro) | All GPU miners | CSI mount for GPU driver libs |
| `hostPath /dev/dri`, `/dev/kfd` | AMD GPU miners | Device plugin or CSI |
| `hostPath /dev` | NVIDIA GPU miners (forge-nvidia) | Device plugin (mounting entire /dev is overly broad) |
| `hostPath /nix/store/...-clr-7.2.0-icd/etc/OpenCL/vendors` | AMD GPU miners | Pin ICD path as CSI volume |
| `hostPath /dev/cpu`, `/dev/hugepages`, `/sys/module/msr` | All xmrig CPU miners | Keep as hostPath (MSR access) or CSI |
| `emptyDir /tmp` | All xmrig CPU miners | Keep as emptyDir |
| `configMap xmrig-proxy-config` | xmrig-proxy | Keep as ConfigMap |
| `secret xmrig-proxy-secret` | xmrig-proxy | Keep as Secret |

### Image Migration Strategy

| Current Image | Deployments | Target |
|--------------|-------------|--------|
| `ubuntu:24.04` + host nix-store | forge-amd-0, forge-amd-1 | Distroless + CSI mount lolminer binary |
| `swamp7/lolminer:latest` | forge-nvidia-0/1, nexus, zephyr | Distroless + CSI mount lolminer binary |
| `xmrig-alpine:6.25.0` (local) | All xmrig (6 deployments) | Distroless + CSI mount xmrig binary |
| `xmrig-proxy:nixos-6.24.0` (local) | xmrig-proxy | Distroless + CSI mount proxy binary |

### Key Nix Store Paths Referenced

| Path | Used By | Purpose |
|------|---------|---------|
| `/nix/store/mpkgc1sk57hmb62qj3dahvmnjag1l3mc-lolminer-1.98a/bin/lolMiner` | forge-amd-0/1 | lolMiner binary |
| `/nix/store/6yvx83sa6iwhr6xnjjlfjg56jnki5mdn-clr-7.2.0-icd/etc/OpenCL/vendors` | forge-amd-0/1 | AMD OpenCL ICD |
| `/run/opengl-driver/lib` | All GPU miners | GPU driver shared libs |
| `/nix/store` (full mount) | All GPU miners | Needed for dependency resolution |

### Per-Host Toleration Summary

| Node | Tolerations |
|------|------------|
| **forge** | none |
| **nexus** | `node-role.kubernetes.io/control-plane:NoSchedule` |
| **zephyr** | `control-plane`, `workstation=true:NoSchedule`, `interactive=true:NoExecute`, `ram-constrained=true:NoSchedule` |
| **sentry** | `node-role.kubernetes.io/control-plane:NoSchedule` |

### Priority Classes

| PriorityClass | Used By | Deployments |
|---------------|---------|-------------|
| `system-cluster-critical` | xmrig-proxy | 1 |
| `mining-low` | All base miners | 9 |
| `preemptible-mining` | All variable miners | 3 |

### Thread Allocation Summary

| Node | Base Threads | Variable Threads | Total / Available |
|------|-------------|-----------------|-------------------|
| zephyr | 8 (xmrig-zephyr) | 8 (xmrig-zephyr-variable) | 16 / 32 (50%) |
| nexus | 6 (xmrig-nexus) | 6 (xmrig-nexus-variable) | 12 / 24 (50%) |
| sentry | 4 (xmrig-sentry) | 4 (xmrig-sentry-variable) | 8 / 16 (50%) |
