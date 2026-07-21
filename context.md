# Mining Deployment Configurations — CSI Migration Reference

## Files Retrieved


---

## Architecture Overview

### Mining Topology

```
                    ┌─────────────────────┐
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

2. **GPU miners** → kryptex CR29 pools **directly** (dual-pool failover: US primary, EU secondary)

### Three Deployment Categories

| Category | Count | Priority | Image Strategy |
|----------|-------|----------|----------------|

---

## Deployment Details

### 1. gpu-miner-forge-amd-0

| Field | Value |
|-------|-------|
| **Image** | `docker.io/library/ubuntu:24.04` |
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

**Volume Mounts:** Identical to amd-0 (same ICD path, same 5 volumes).

---

### 3. gpu-miner-forge-nvidia-0

| Field | Value |
|-------|-------|
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


| Field | Value |
|-------|-------|
| **Command** | (default entrypoint) |
| **Args** | `-o 10.1.1.120:3333 -u nexus-cpu --tls=false --threads=6 --donate-level=1 --http-enabled --http-host=0.0.0.0 --http-port=8082` |
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


| Field | Value |
|-------|-------|
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


---


| Field | Value |
|-------|-------|
| **Command** | (default entrypoint) |
| **Args** | `-o 10.1.1.120:3333 -u sentry-cpu --tls=false --threads=4 --donate-level=1 --http-enabled --http-host=0.0.0.0 --http-port=8081` |
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


| Field | Value |
|-------|-------|
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


| Field | Value |
|-------|-------|
| **Args** | (inline via command) |
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


| Field | Value |
|-------|-------|
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
| **Probes** | none |

**Volume Mounts:** Same pattern (msr + hugepages + sys-module-msr + tmp).


---


| Field | Value |
|-------|-------|
| **Command** | (default entrypoint) |
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

---



**config.json contents:**

```json
{
  "bind": [{"host": "0.0.0.0", "port": 3333}],
  "api": {
    "port": 8081,
    "restricted": true,
  },
  "randomx": {"mode": "light"},
  "log": {"level": 5},
  "pools": [
    {
      "id": "kryptex-rx-us",
      "url": "xtm-rx-us.kryptex.network:8038",
      "user": "krxXVNVMM7.cpu-proxy",
      "tls": true, "keepalive": true, "priority": 1
    },
    {
      "id": "kryptex-rx-eu",
      "url": "xtm-rx-eu.kryptex.network:8038",
      "user": "krxXVNVMM7.cpu-proxy",
      "tls": true, "keepalive": true, "priority": 2
    },
    {
      "id": "kryptex-cr29-us",
      "url": "xtm-c29-us.kryptex.network:8040",
      "user": "krxXVNVMM7.gpu-proxy",
      "tls": true, "keepalive": true, "priority": 1
    },
    {
      "id": "kryptex-cr29-eu",
      "url": "xtm-c29-eu.kryptex.network:8040",
      "user": "krxXVNVMM7.gpu-proxy",
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

### Image Migration Strategy

| Current Image | Deployments | Target |
|--------------|-------------|--------|

### Key Nix Store Paths Referenced

| Path | Used By | Purpose |
|------|---------|---------|
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
| `mining-low` | All base miners | 9 |
| `preemptible-mining` | All variable miners | 3 |

### Thread Allocation Summary

| Node | Base Threads | Variable Threads | Total / Available |
|------|-------------|-----------------|-------------------|
