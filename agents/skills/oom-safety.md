# Zephyr OOM safety

**Last verified:** 2026-08-16

Zephyr has 31GB and constant RAM pressure (control plane + AI + gaming). The
fleet's memory defense is layered, in kill/priority order:

| Layer | Mechanism | Where |
|-------|-----------|-------|
| 1 | **earlyoom** — fast percentage-based RAM+swap kill, `--avoid` graphical session + gaming, `--prefer` browser/nix | `modules/system/vm-tuning.nix`, `hosts/zephyr/configuration.nix` |
| 2 | **systemd-oomd** — PSI-based; `MemoryUsedPercent=90`, `SwapUsedPercent=85` (percent keys only) | `modules/system/oomd-fleet.nix` |
| 3 | **cgroup caps** — MemoryHigh/MemoryMax on slices and units (user@1000 28G/30G, nix.slice 80%, gaming.slice 90%, mining.slice 8G) | `modules/system/systemd-slices.nix` |
| 4 | **oom_score_adj / OOMPolicy** — kernel scoring; bonsai volunteers to die first (+500), unbound/gaming/user session protected | `modules/system/oom-protection.nix` |
| + | **vm.\* sysctls** — overcommit=0, min_free_kbytes=1G, zram 50% ≈ 15.6G on zephyr | `modules/system/vm-tuning.nix` |

## Rules when touching memory config

- oomd keys are **percent-based** in NixOS 26.11. Integer keys like
  `SwapUsedLimit=90` are silently ignored — never restore them.
- `noctalia.service` keeps `ManagedOOMSwap=off` (oomd killed it twice).
- Do not run builds in `systemd-run --user` on a host with user-session services;
  a user-session OOM killed `user@1000.service` and the build with it. Use root units.
- Schedule non-essential K8s workloads to Nexus, not Zephyr (see
  `agents/skills/add-k8s-workload.md`).
