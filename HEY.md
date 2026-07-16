# HEY.md — Cross-Agent Coordination

**Purpose:** Shared scope coordination for multiple AI agents (different
sessions, models, or vendors). Read this before working. Update when done.

**Last updated:** 2026-07-16 00:15

---

## Active Sessions

| Agent | Scope | Files/hosts touched | Off-limits | Status | Last active |
|-------|-------|---------------------|------------|--------|-------------|
| zephyr-kernel-proxy-build | Upgrade zephyr kernel to CachyOS 7.1.3; fix proxy/store corruption; unbreak distributed builds | flake.nix, flake.lock, configuration.nix, distributed-builds.nix, nix-config.nix, stylix.nix, hermes-cli.nix, herdr.nix, justfile, osaka-jade.yaml | forge/mining services, sentry inference, k3s-cluster, niri-config | ✅ Core fixes done; ⏳ build v6 running (kernel compiling) | 2026-07-16 00:15 |
| nexus-dns-and-hermes | k3s host-gw fix, hermes model mapping, cluster DNS | k3s-cluster.nix, cluster-dns.nix, home-manager.nix | forge/sentry services, niri-config | ✅ Done | 2026-07-15 14:00 |
| maplespike-24-issues | 24 MapleSpike production issues across quill + nixos-config | quill repo, nixos-config k8s manifests | k3s-cluster.nix, flannel, DNS, forge/sentry, niri-config | ✅ Done (llama.cpp CUDA build pending via tmux) | 2026-07-15 |

---

## Active Decisions

| ID | Decision | Rationale | Agent | Date |
|----|----------|-----------|-------|------|
| D1 | Use `git+https://` not `github:` for flake inputs | curl-42 abort on tarball API (api.github.com) | j_kro | 2026-07-15 |
| D2 | Remove `--substitute-on-destination` from post-build-hook | Truncated nars cached as valid paths (NixOS/nix#2389) | j_kro | 2026-07-15 |
| D3 | Builders: nexus+sentry only — no forge (mining), no krash3 (Windows) | Builds compete with mining; krash3 is Windows-only | j_kro | 2026-07-15 |
| D4 | Remove `http://10.1.1.120:50000` from substituters declaratively | nix-serve served truncated nars from corrupted store; nix-serve auto-restarts but must not be in substituter list | j_kro | 2026-07-15 |
| D5 | Build locally with `--impure` for freebuff-desktop | AppImage path access forbidden in pure eval (pre-existing issue) | j_kro | 2026-07-15 |

---

## Work Log

All entries are UTC-5 (CDT). Use this format going forward: `### YYYY-MM-DD HH:MM (UTC±H) | agent-name`

### 2026-07-16 00:00 (UTC-5) | zephyr-kernel-proxy-build
- 🔄 Build v6 still running (PID 3827510 on nexus, 549 log lines) — CachyOS 7.1.3 kernel compiling on sentry
- ✅ nix-serve auto-restarted but removed from substituters — local cache works for clean paths only
- ✅ krash3/forge removed from machines files + daemon restarted cluster-wide
- ✅ HEY.md reformatted to /hey spec with timestamp columns

### 2026-07-15 22:30 (UTC-5) | zephyr-kernel-proxy-build
- 🔄 Build v6 started on nexus coordinator
- ✅ All 9 eval blockers fixed (curl-42, stylix, YAML, freebuff, ruamel, hermes-secrets, logrotate, krash3, forge)
- ✅ All session fixes committed + pushed to central/origin

### 2026-07-15 14:00 (UTC-5) | nexus-dns-and-hermes
- ✅ k3s-host-gw fix committed (`ddde68cf`), cluster DNS fixed, hermes model mapping fixed
- ✅ flannel.conf machinery removed

### 2026-07-15 | maplespike-24-issues
- ✅ 24 MapleSpike issues implemented, rolled out

---

## Handoff

**From:** zephyr-kernel-proxy-build
**Timestamp:** 2026-07-16 00:15 (UTC-5)
**Status:** ✅ Core fixes done; ⏳ build v6 still running
**What changed:**
- CachyOS 7.1.3 kernel pin + zephyr override — resolves to `linux-cachyos-latest-x86_64-v3-7.1.3`
- Corrupt proxy (`10.1.1.120:50000`) removed from nix.conf on all hosts (declaratively)
- Post-build-hook `--substitute-on-destination` removed — corruption writer fixed
- All 9 eval blockers fixed cluster-wide
- Builders reduced to nexus+sentry only (no forge/mining, no krash3)
- Builder retune: nexus 12→16, sentry 8→10 (source only, needs switch)
- HEY.md spec formalized with timestamp columns

**What's blocked:**
- Final build toplevel not yet produced — kernel still compiling on sentry
- No deploy per user instruction — toplevel artifact only

**What to do next:**
1. Wait for build v6 (PID 3827510 on nexus, sentry compiling kernel) to complete
2. If the toplevel store path appears, report it; do NOT switch
3. If the build fails, check the log at `/tmp/zephyr-nexus-v6-log` on nexus
4. The committed config changes need `just deploy nexus sentry` to take effect — hold per user's "no redeploy"
5. Consider switching remaining flake `github:` URLs to `git+https://` for consistency (batch sed)
6. Open a GitHub issue for the nix-serve store corruption root cause

**Files touched:**
- `flake.nix`, `flake.lock`, `hosts/zephyr/configuration.nix`, `modules/desktop/stylix.nix`
- `modules/desktop/themes/osaka-jade.yaml`, `modules/services/hermes-cli.nix`
- `modules/system/distributed-builds.nix`, `modules/system/nix-config.nix`
- `packages/herdr.nix`, `justfile`, `HEY.md`
