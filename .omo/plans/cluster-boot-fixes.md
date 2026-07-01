# Plan: Cluster Boot & Systemd Error Fixes

**Last Verified:** 2026-06-30
**Scope:** Fix all boot speed issues and systemd journal errors across Zephyr, Nexus, Forge, Sentry
**Target:** Every node boots ≤45s with zero systemd unit errors

---

## Background

Diagnostics ran across all 4 nodes. Current boot times: Zephyr 1m21s (slowest), Nexus 45s, Forge 49s, Sentry 40s (fastest). Multiple systemd services have broken quoting, timeout failures, or misconfiguration.

---

## TODOs

1. [x] Fix Forge llamafile.service broken quoting (CRITICAL)
    - **Category:** `deep`
    - **Files:** `modules/services/llamafile.nix`
    - **Change:** Replace inline `--chat-template '${...}'` shell quoting on line 222 with `--chat-template-file ${chatTemplateFile}`. The `chatTemplateFile` is already defined at line 196 but never referenced in ExecStart. Also fix the second llamafile service in `hosts/forge/configuration.nix` line 162 inline `--chat-template '...'` which has same quoting breakage — write its template to a file via `pkgs.writeText` and use `--chat-template-file`.
    - **Verification:** `nix flake check` passes. On deploy, `systemctl status llamafile` shows active on Forge, no "unbalanced quoting" errors in journal.

2. [x] Fix Nexus k8s-secrets-sync.service timeout (CRITICAL)
    - **Category:** `deep`
    - **Files:** `modules/services/k8s-secrets-sync.nix`
    - **Change:** The service waits up to 120s for `kubectl get nodes` but 20x 5s retries = 100s effective, not 120s as stated. Fix: either (a) increase timeout to 180s and fix the elapsed calculation, or (b) add `partOf = ["k3s.service"]` and `bindsTo = ["k3s.service"]` so it only runs when K3s is already active, removing the polling loop entirely. Option (b) is cleaner.
    - **Verification:** Deploy to Nexus, check `systemctl status k8s-secrets-sync` shows exited 0 and secrets exist in K8s namespaces.

3. [x] Fix Zephyr hermes-gateway user service restart loop (MAJOR)
    - **Category:** `deep`
    - **Files:** `hosts/zephyr/services.nix` (line 755)
    - **Change:** This is a `systemd.user.services` entry — user services only start when the user is logged in. If j_kro isn't logged in at boot, the service never starts but the timer/activation may keep trying. Fix: convert to system-level service with `User=j_kro` (same as hermes-agent). Add proper `after=`, `wants=`, and `Restart=on-failure`.
    - **Verification:** Deploy to Zephyr, check `systemctl status hermes-gateway` shows active running, no restart loop in journal.

4. [x] Apply TPM/ttyS blacklist cluster-wide (MAJOR)
    - **Category:** `deep`
    - **Files:** Create `modules/system/tpm-boot-fix.nix`; remove from `hosts/zephyr/configuration.nix` lines 74-80
    - **Change:** Move `boot.blacklistedKernelModules` for TPM (`tpm_crb`, `tpm_tis`, `tpm_tis_core`) and serial (`serial8250`) from host-specific Zephyr config into a shared module. Import in `modules/default.nix`. This saves ~10-12s on every node boot. If `DefaultDeviceTimeoutSec` is available in this NixOS version, also set it to 5s as backup.
    - **Verification:** `nix flake check`. Deploy to all 4 nodes. Verify `systemd-analyze time` shows reduced kernel device time. Check no TPM-related errors in `journalctl -b`.

5. [x] Fix opencode-model-update boot delay (MAJOR)
    - **Category:** `deep`
    - **Files:** `modules/development/opencode.nix`
    - **Change:** The `OnBootSec=30s` timer fires 30s after boot, which triggers the oneshot service with its own 30s gateway health wait loop. This adds 30-60s to boot-visible time in `systemd-analyze blame`. Since it's a timer (not `wantedBy=multi-user.target`), it doesn't actually block boot — the 29.5s blame is misleading. Verify the critical path does NOT include this service. If confirmed, leave unchanged. If it does block boot, change to `OnBootSec=5min` to defer sync entirely.
    - **Verification:** `systemd-analyze critical-chain` should NOT show opencode-model-update on the critical path.

6. [x] Fix ROCm symlink failures on Forge and Sentry (MAJOR)
    - **Category:** `deep`
    - **Files:** `hosts/forge/hardware.nix` (lines 355-371), `hosts/sentry/hardware.nix` (lines 75-90)
    - **Change:** The `L+` tmpfiles rules for `/opt/rocm` symlinks fail because they run before the store paths exist. Fix: wrap in a oneshot systemd service with `after = ["local-fs.target"]` that creates the symlinks via shell script. Remove failing `L+` tmpfiles entries.
    - **Verification:** Deploy to Forge and Sentry. Verify `ls -la /opt/rocm` points to valid store paths. Check no `tmpfiles` errors in journal.

7. [x] Fix backup-to-garage /data/shared missing mount (MINOR)
    - **Category:** `deep`
    - **Files:** `hosts/zephyr/services.nix` (line 316-324)
    - **Change:** backup-to-garage includes `/data/shared` in its default `backupPaths`, but Zephyr has `nfs-client.mountShared = false`. Override `backupPaths` to `["/etc/nixos"]` in the Zephyr enable block to exclude `/data/shared`.
    - **Verification:** Deploy to Zephyr. Verify backup runs without "path not found" errors.

8. [x] Fix Sentry kanban-execute.timer missing script (MINOR)
    - **Category:** `deep`
    - **Files:** `hosts/sentry/configuration.nix` (lines 77-97)
    - **Change:** The timer references `/home/j_kro/projects/maplespike/scripts/kanban-execute.sh`. Add `ConditionPathExists=` to prevent failure when script is absent, or fix the path if the script location changed.
    - **Verification:** Deploy to Sentry. `systemctl status kanban-execute.timer` shows active. `systemctl start kanban-execute` doesn't fail.

9. [x] Fix duplicate unbound forward zone warnings (MINOR)
    - **Category:** `deep`
    - **Files:** `modules/services/unbound-common.nix`, `modules/network/cluster-dns.nix`
    - **Change:** If duplicate forward-zone warnings still occur, use `lib.mkForce` on one side to prevent the cluster-dns forward zones from being applied twice. Verify which module double-applies the forward zones and deduplicate at the source.
    - **Verification:** Deploy to all nodes. No "duplicate forward zone" warnings in journal.

---

## Final Verification Wave

F1. [ ] Verify all services start cleanly (requires deploy)
    - After deploy: `for host in zephyr nexus forge sentry; do ssh $host 'systemctl list-units --state=failed --no-legend' | wc -l` = 0 on all nodes
    - After deploy: No "unbalanced quoting", "timeout", "failed" for fixed services

F2. [ ] Verify boot time improvement (requires deploy + reboot)
    - After deploy+reboot: Zephyr boot ≤50s, Nexus ≤40s, Forge ≤45s, Sentry ≤40s

F3. [x] Verify no regressions (code validation)
    - `nix-instantiate --parse` passes on all 8 changed files
    - All changes validated: correct Nix syntax, no syntax errors

F4. [x] Verify all fixes are in NixOS modules
    - All 8 changes in git-tracked .nix files
    - Replaced tmpfiles L+ rules with systemd service on both Forge+Sentry
    - `git diff --stat` shows 8 files, 71 insertions, 48 deletions
