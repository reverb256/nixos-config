# HEY.md — Cross-Agent Coordination

**Purpose:** Shared scope coordination for multiple AI agents (different
sessions, models, or vendors). Read this before working. Update when done.

**Last updated:** 2026-07-16 00:20 (UTC-5)

---

## Active Sessions

| Agent | Scope | Files/hosts touched | Off-limits | Status | Last active |
|-------|-------|---------------------|------------|--------|-------------|
| j_kro-systemd_recovery | Sentry crash investigation + cluster k3s recovery | modules/system/kernel-hardening.nix, hosts/sentry/configuration.nix, hosts/sentry/services.nix, hosts/forge/services.nix, modules/development/ai-coding-tools/droid.nix, modules/system/sops-secrets-registry.nix | Peakminer/mining services, MapleSpike, Niri desktop configs | ✅ Cluster restored (nexus+forge+sentry); ✅ etcd quorum fixed (identity-only encryption); ✅ Forge agent config committed; ✅ Sentry panic=30 config committed; 🔄 Sentry k3s still cycling (3-member etcd formed, k3s not fully becoming Ready) | 2026-07-21 05:05 (UTC-5) |

(Stale prior sessions archived — nexus-dns-and-hermes, maplespike-24-issues, nexus-de-vm-boot, infra/dns-recovery, quill-portal-fixes were all ✅ Done from earlier sessions.)

---

## Active Decisions

| ID | Decision | Rationale | Agent | Date |
|----|----------|-----------|-------|------|
| D1 | Use `git+https://` not `github:` for flake inputs | curl-42 abort on tarball API (api.github.com) | j_kro | 2026-07-15 |
| D2 | Remove `--substitute-on-destination` from post-build-hook | Truncated nars cached as valid paths (NixOS/nix#2389) | j_kro | 2026-07-15 |
| D3 | Builders: nexus+sentry only — no forge (mining), no krash3 (Windows) | Builds compete with mining; krash3 is Windows-only | j_kro | 2026-07-15 |
| D4 | Remove `http://10.1.1.120:50000` from substituters declaratively | nix-serve served truncated nars from corrupted store | j_kro | 2026-07-15 |
| D5 | Build locally with `--impure` for freebuff-desktop | AppImage path access forbidden in pure eval (pre-existing) | j_kro | 2026-07-15 |
| D6 | Remove boot-time VFIO module loading on nexus; VFIO loads on demand | GPU boots on nvidia for AI inference; VFIO loaded by handoff script at VM start | j_kro | 2026-07-16 |

---

## Work Log

### 2026-07-21 05:05 (UTC-5) | j_kro-systemd_recovery
- ✅ Sentry crash investigation: MCE on CPU 1 Bank 5 (Execution Unit, Jul 17), 2nd crash was hardware-level reset (PSU/thermal, no panic logs)
- ✅ Cluster k3s recovery: etcd quorum fixed after cluster-reset on nexus; encryption config set to identity-only
- ✅ etcd stale members removed (sentry, forge); cluster-reset recovery performed on nexus
- ✅ Forge role config changed server→agent (committed `1a2211cb`, needs deploy)
- ✅ Sentry panic=30 added to kernel params (committed `e10af411`)
- ✅ Auth fixed: zephyr kubeconfig updated with new cluster certs
- ✅ droid.nix JSON double-comma fixed (already in HEAD)
- 🔄 Sentry k3s still cycling: 3-member etcd formed but k3s server not reaching Ready state
- 🔄 Sentry's `/run/secrets/k3s-cluster-token` needs sops deployment or manual copy

### 2026-07-20 17:00 (UTC-5) | j_kro (quill-WebMCP-fixes)
- ✅ WebMCP implemented (7 tools), deployed to k3s
- ✅ API crash loop fixed (rate limit bypass + readiness probe fix)
- ✅ Portal→API proxy fixed (X-Forwarded-Proto: https)
- ✅ Cloudflare DNS fixed (Pages CNAME → Tunnel CNAME)
- ✅ Caveman + Cavecrew completely removed system-wide
- 🔄 Sentry k3s still failing to join cluster (duplicate node name)
- 🔄 NixOS config fixes committed but not deployed (noctalia, calico, syncthing deviceId, garage rpcSecret)

**Files touched:**
- `flake.nix`, `hosts/nexus/configuration.nix`, `modules/services/k3s-cluster.nix`
- `modules/services/syncthing.nix`
- `~/Projects/quill/packages/portal/*`, `~/Projects/quill/packages/api-server/src/*`
- `~/.config/opencode/*`, `~/.claude/*`, `~/.grok/*`, `~/.skillclaw/*`
- `~/Projects/hermes-skills/*`, `~/.agents/skills/*`, `~/.npm/_npx/*`
- `~/.claude.json`, `~/.config/opencode/AGENTS.md`
- Cloudflare DNS, cache level, dev mode

### 2026-07-15 22:30 (UTC-5) | zephyr-kernel-proxy-build
- 🔄 Build v6 started on nexus coordinator (nexus+sentry builders, no forge/krash3)
- ✅ All 9 eval blockers fixed (curl-42, stylix, YAML, freebuff, ruamel, hermes-secrets, logrotate, krash3, forge)
- ✅ All session fixes committed + pushed to central/origin

---

## Handoff

**From:** zephyr-kernel-proxy-build
**Timestamp:** 2026-07-16 00:20 (UTC-5)
**Status:** ✅ Core fixes done; ⏳ build v6 running
**What changed:**
- CachyOS 7.1.3 kernel pin + zephyr override — resolves to `linux-cachyos-latest-x86_64-v3-7.1.3`
- Corrupt proxy (`10.1.1.120:50000`) removed from nix.conf on all hosts (declaratively)
- Post-build-hook `--substitute-on-destination` removed — corruption writer fixed
- All 9 eval blockers fixed cluster-wide
- Builders reduced to nexus+sentry only (no forge/mining, no krash3)
- Builder retune: nexus 12→16, sentry 8→10 (source only, needs switch)

**What's blocked:**
- Final build toplevel not yet produced — kernel still compiling on sentry
- No deploy per user instruction — toplevel artifact only

**What to do next:**
1. Wait for build v6 (PID 3827510 on nexus, sentry compiling kernel) to complete
2. If the toplevel store path appears, report it; do NOT switch
3. If the build fails, check `/tmp/zephyr-nexus-v6-log` on nexus
4. Committed config changes need `just deploy nexus sentry` to take effect — held per "no redeploy"
5. Consider switching remaining flake `github:` URLs to `git+https://` for consistency

**Files touched:**
- `flake.nix`, `flake.lock`, `hosts/zephyr/configuration.nix`, `modules/desktop/stylix.nix`
- `modules/desktop/themes/osaka-jade.yaml`, `modules/services/hermes-cli.nix`
- `modules/system/distributed-builds.nix`, `modules/system/nix-config.nix`
- `packages/herdr.nix`, `justfile`, `HEY.md`
