# NixOS Config Simplification Plan

> **⚠️ STALE (24 days old, last verified 2026-04-29)** — Verify against current cluster state before following. Reality may have diverged.

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Remove ~500 lines of dead config, 42 dead module files, 173 archived K8s manifests, and deduplicate ~170 lines of repeated code across hosts.

**Architecture:** Five phases, each with a git commit. Phase 1-2 are safe deletions (no behavioral change). Phase 3 removes dead config blocks (no behavioral change — all `enable = false`). Phase 4 is deduplication (extracts shared modules). Phase 5 is cleanup (firewall, comments, K8s manifests).

---

## Phase 1: Delete Dead Module Files

**Commit:** `refactor: remove 38 dead module files`

No behavioral change — none of these files are imported anywhere.

### Task 1.1: Delete dead lib/ files (4 files)

modules/lib/advanced-types.nix, firewall-helpers.nix, option-helpers.nix, systemd-helpers.nix

### Task 1.2: Delete dead system/ files (9 files)

modules/system/dns-watchdog.nix, interface-naming.nix, nix-settings.nix, pi-models.nix, systemd-slices.nix, virtualisation.nix, common-host.nix, pi-models.nix.archive, compute-workload-monitor.nix.backup

### Task 1.3: Delete dead network/ files (3 files)

modules/network/bluetooth.nix, networkmanager-dns.nix, wifi.nix

### Task 1.4: Delete dead services/ files (17 files)

modules/services/auto-secrets.nix, brain-critic.nix, claude-auto-update.nix, cluster-monitoring.nix, crash-watchdog.nix, gaming-mining-coordinator.nix, haproxy-ingress.nix, haproxy-lb.nix, health-checks.nix, hermes-dashboard.nix, hermes-webui.nix, k8s-manifest-autoapply.nix, podman.nix, qwen3-tts-preload.nix, monitoring/promtail.nix, mcp-servers.nix, unbound-cluster.nix.backup.disabled, unbound-cluster.nix.disabled

### Task 1.5: Delete dead desktop/ files (1 file)

modules/desktop/gamescope-tty.nix

### Task 1.6: Delete dead development/ files (2 files)

modules/development/ai-coding-tools/pi.nix, pi.nix.archive

### Task 1.7: Delete dead profiles/ and virtualization/ files (2 files)

modules/profiles/node-profiles-test.nix, modules/virtualization/microvm-host.nix

### Task 1.8: Delete dead monitoring archive (1 file)

modules/services/monitoring/grafana.nix.archive

### Task 1.9: Clean commented-out imports in modules/default.nix

Remove commented import lines for files that still exist on disk and were never imported:
- `# ./desktop/plasma6.nix` — also delete the .nix file
- `# ./desktop/systems-intelligence-plasmoid.nix` — also delete the .nix file
- `# ./mining/mining-plasmoid.nix` — also delete the .nix file
- `# ./services/mcp-servers.nix` — already deleted in 1.4, just remove comment

### Task 1.10: Delete dead host files (5 files)


### Task 1.11: Verify and commit

```bash
cd /etc/nixos && sudo git add -A && sudo nix flake check --no-build 2>&1 | tail -5
sudo git commit -m "refactor: remove 38 dead module files and 5 dead host files"
```

---

## Phase 2: Delete Dead Config Blocks (enable = false)

**Commit:** `refactor: remove disabled service blocks from host configs`

### Task 2.1: Clean zephyr/services.nix (~164 lines)

Remove: compute-market (enable=false), gateway.knowledgeFabric (enable=false), mcp (enable=false), rag (enable=false), llamafile (enable=false, "migrated to k8s")

### Task 2.2: Clean zephyr/configuration.nix (~10 lines)

Remove: commented-out nix-mineral and microvm-host imports and config block

### Task 2.3: Clean nexus/services.nix (~100 lines)


### Task 2.4: Clean sentry/services.nix (~31 lines)

Remove: mining blocks (enable=false), llamafile (enable=false), redundant systemd overrides (already disabled by mkForce false)

### Task 2.5: Clean forge/services.nix (~15 lines)


### Task 2.6: Clean forge/hardware.nix (~24 lines)

Remove: amd-gpu-max-fan service (DISABLED per comment), empty boot.kernelParams = []

### Task 2.7: Clean forge/configuration.nix (~4 lines)

Remove: commented-out nix-mineral block

### Task 2.8: Verify and commit

```bash
cd /etc/nixos && sudo git add -A && sudo nix flake check --no-build 2>&1 | tail -5
sudo git commit -m "refactor: remove disabled service blocks from host configs"
```

---

## Phase 3: Deduplicate Shared Config

**Commit:** `refactor: extract shared ROCm and nix-mineral modules`

### Task 3.1: Create modules/hardware/rocm-compat.nix

Extract intersection of forge and sentry ROCm blocks: nix-ld.libraries, env vars, tmpfiles.rules. Use mkOption for host-specific extras (forge has extra rules for /dev/net/tun and OpenCL vendors).

### Task 3.2: Replace ROCm blocks in forge and sentry

Remove duplicated blocks from both hosts, import rocm-compat.nix, set enable=true, add forge-specific extras inline.

### Task 3.3: Create modules/system/nix-mineral-gitconfig-fix.nix

Extract gitconfig override shared by nexus and sentry. Import in both, remove duplicated blocks.

### Task 3.4: Verify and commit

```bash
cd /etc/nixos && sudo git add -A && sudo nix flake check --no-build 2>&1 | tail -5
sudo git commit -m "refactor: extract shared ROCm and nix-mineral modules"
```

---

## Phase 4: K8s Manifest Cleanup

**Commit:** `refactor: remove 173 archived K8s manifests and stale resources`

### Task 4.1: Delete kubernetes-manifests/archive/ (173 files)

### Task 4.2: Delete stale active manifests

istio-zephyr.yaml, scheduling/yunikorn/, scheduling/volcano/, storage/nix-csi-test-pod*.yaml, test/

### Task 4.3: Verify and commit

```bash
cd /etc/nixos && sudo git add -A && sudo git commit -m "refactor: remove archived K8s manifests and stale resources"
```

---

## Phase 5: Firewall, Monitoring, and Script Cleanup

**Commit:** `refactor: deduplicate firewall, clean stale scripts`

### Task 5.1: Remove duplicate port 9100 from all 4 monitoring.nix

Verify 9100 is opened in firewall.nix, then remove from monitoring.nix allowedTCPPorts.

### Task 5.2: Clean zephyr/firewall.nix overlap

Remove ports from allowedTCPPorts that are already in extraInputRules.

### Task 5.3: Remove redundant monitoring import from all 4 hosts

Each monitoring.nix re-imports modules/services/monitoring/default.nix which is already in modules/default.nix. Remove the imports line.

### Task 5.4: Archive 8 one-time scripts to scripts/archive/

docs-emergency-cleanup.sh, remove-flannel-annotations.sh, install-lmstudio-headless.sh, setup-lmstudio-secret.sh, phase1-velero-install.sh, create-garage-buckets.sh, encrypt-garage-secret.sh, lmstudio-api-examples.py

### Task 5.5: Remove dead check_flannel() from cleanup-zombie-pods.sh


Remove or update localhost targets for disabled mining services.

### Task 5.7: Move sentry videoDrivers from services.nix to hardware.nix

### Task 5.8: Verify and commit

```bash
cd /etc/nixos && sudo git add -A && sudo nix flake check --no-build 2>&1 | tail -5
sudo git commit -m "refactor: deduplicate firewall, clean stale scripts and monitoring targets"
```

---

## Phase 6: Full Validation

### Task 6.1: `sudo nix flake check --no-build` — must pass
### Task 6.2: Grep all imports — verify no broken references
### Task 6.3: Count remaining files for comparison

---

## Summary

| Phase | What | Risk |
|-------|------|------|
| 1 | Delete 42 dead module/host files | None (never imported) |
| 2 | Remove ~500 lines of enable=false blocks | None (disabled) |
| 3 | Extract shared ROCm + nix-mineral modules | Low (same code, new location) |
| 4 | Delete 173+ K8s manifest archives | None (archive) |
| 5 | Firewall dedup, script archive, monitoring fix | Low (verify ports) |
| 6 | Full validation | None |

**Total: ~750 lines of dead code removed, 215+ files deleted, 170 lines deduplicated.**
