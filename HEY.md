# HEY.md — Cross-Agent Coordination

**Purpose:** Shared scope coordination for multiple AI agents (different
sessions, models, or vendors). Read this before working. Update when done.

**Last updated:** 2026-07-15 22:30

---

## Active Sessions

| Agent | Scope | Files touched | Off-limits | Status |
|-------|-------|---------------|------------|--------|
| zephyr-kernel-proxy-build | Upgrade zephyr kernel to CachyOS 7.1.3, fix proxy/store corruption, fix eval blockers | flake.nix, flake.lock, configuration.nix, distributed-builds.nix, nix-config.nix, stylix.nix, hermes-cli.nix, herdr.nix, justfile, osaka-jade.yaml | forge/mining services, sentry inference, k3s-cluster, niri-config | ⏳ build finishing (see Handoff) |
| nexus-dns-and-hermes | k3s-flannel fix, hermes config, cluster DNS | k3s-cluster.nix, cluster-dns.nix, home-manager.nix | forge, sentry services, niri-config | ✅ Done |
| maplespike-24-issues | 24 MapleSpike production issues | quill repo + nixos-config k8s manifests | k3s-cluster.nix, flannel, DNS, forge/sentry, niri-config | ✅ Done (llama.cpp build pending) |

---

## Active Decisions

| ID | Decision | Rationale | Agent | Date |
|----|----------|-----------|-------|------|
| D1 | Use `git+https://` not `github:` for flake inputs | curl-42 abort on tarball API (api.github.com) | j_kro | 2026-07-15 |
| D2 | Remove `--substitute-on-destination` from post-build-hook | Truncated nars cached as valid paths (NixOS/nix#2389) | j_kro | 2026-07-15 |
| D3 | Builders: nexus+sentry only, no forge/mining | Builds compete with mining revenue | j_kro | 2026-07-15 |
| D4 | Stop nix-serve on nexus, remove from substituters | Served truncated nars from corrupted store | j_kro | 2026-07-15 |

---

## Work Log

### 2026-07-15 22:30 | zephyr-kernel-proxy-build
- 🔄 Build v6 running on nexus coordinator (pid 3827510) — CachyOS 7.1.3 kernel compiling on sentry
- ✅ All 9 eval blockers fixed (curl-42, stylix, YAML, freebuff, ruamel, hermes-secrets, logrotate, krash3, forge)
- ✅ All fixes committed + pushed to central/origin (commit range `dd877f0c..ee1b1028`)
- ✅ krash3/forge removed from distributed builders, daemon restarted cluster-wide

### 2026-07-15 14:00 | nexus-dns-and-hermes
- ✅ k3s-host-gw fix committed (`ddde68cf`), cluster DNS fixed, hermes model mapping fixed
- ✅ flannel.conf machinery removed

### 2026-07-15 | maplespike-24-issues
- ✅ 24 MapleSpike issues implemented, rolled out, llama.cpp build in progress (tmux zephyr)

---

## Handoff

**From:** zephyr-kernel-proxy-build
**Status:** ✅ Core fixes done, build finishing
**What changed:**
- CachyOS 7.1.3 kernel pin + zephyr override — resolve to `linux-cachyos-latest-x86_64-v3-7.1.3`
- Corrupt proxy removed from nix.conf on all hosts (declaratively + live)
- Post-build-hook `--substitute-on-destination` removed — was the corruption writer
- All 9 eval blockers fixed cluster-wide
- Builders reduced to nexus+sentry only (no forge/mining, no krash3)
- Builder retune: nexus 12→16, sentry 8→10 (source only, needs switch)
- HEY.md spec formalized + skill created

**What's blocked:**
- Final build toplevel not yet produced (kernel compiling on sentry)
- No deploy per user instruction — toplevel artifact only

**What to do next:**
1. Wait for build v6 (pid 3827510 on nexus, sentry compiling kernel) to complete
2. If the toplevel store path appears, report it; do NOT switch
3. If the build fails with a new eval error, fix it and retry
4. The committed config changes need a `just deploy` (nexus+sentry+forge) to take effect — hold per user's "no redeploy"
5. Consider switching the remaining flake input `github:` URLs to `git+https://` as a batch for consistency
6. Open a GitHub issue for the nix-serve store corruption root cause

**Files touched:**
- `flake.nix`, `flake.lock`, `hosts/zephyr/configuration.nix`, `modules/desktop/stylix.nix`
- `modules/desktop/themes/osaka-jade.yaml`, `modules/services/hermes-cli.nix`
- `modules/system/distributed-builds.nix`, `modules/system/nix-config.nix`
- `packages/herdr.nix`, `justfile`, `HEY.md`
