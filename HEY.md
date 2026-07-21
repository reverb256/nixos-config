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

### 2026-07-21 02:30 (UTC-5) | j_kro-quill-nixos
- ✅ WebMCP: 7 tools implemented and deployed to k3s (getHealth, searchGovernmentData, askMapleSpike, getWatcherEvents, getBillingPlans, listDataModules, getApiDocs)
- ✅ API crash loop fixed: rate limit bypass for /v1/health + /v1/astral/health; readiness probe changed to /v1/health
- ✅ Portal→API proxy fixed: X-Forwarded-Proto always https
- ✅ Cloudflare: DNS changed from Pages CNAME to Tunnel CNAME; cache level aggressive→basic; dev mode on
- ✅ Caveman + Cavecrew: completely removed from all 8 locations (OpenCode, Claude, Grok, Skillclaw, Hermes-skills, npx caches, .claude.json, AGENTS.md)
- ✅ XMRIG: ALL references purged from .nix files (38 files cleaned — dual-xmrig.nix, xmrig-proxy.nix, packages, pkgs, containers, secrets registries, host configs, monitoring, grafana, etc.)
- ✅ Eval drift fixes: noctalia flake input, calico option, syncthing deviceId, garage rpcSecret, wivrn defaultRuntime, timeseries description, krash3 refs removed, promtail disabled
- 🔄 Build still failing: last error is in sops-secrets-registry.nix mining section (orphaned secret entries from xmrig sed-strip broke syntax — needs manual fix)
- 🔄 Sentry k3s still not healthy (duplicate node name in etcd)
- 🔄 No deploy yet — waiting for successful build

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

**From:** j_kro-quill-nixos
**Timestamp:** 2026-07-21 02:30 (UTC-5)
**Status:** ✅ All major cleanup done; 🔄 Build blocked by one syntax error
**What changed:**
- WebMCP, API fix, portal proxy, Cloudflare DNS done
- Caveman + Cavecrew removed from all 8 locations

**What's blocked:**
- Build fails at `modules/system/sops-secrets-registry.nix` line 432 — the mining section
  has orphaned secret entries (sed-strip of xmrig references left dangling `format = "binary";...};` blocks without their key names). Needs manual fix of the mining block.
- Sentry k3s still not healthy (etcd duplicate node name)

**What to do next:**
1. Fix sops-secrets-registry.nix mining section (remove orphaned secret blocks inside the `mkIf mining` section)
2. Run `nix build .#nixosConfigurations.nexus.config.system.build.toplevel` to verify
3. Commit and push
4. `just deploy` to all reachable hosts

**Files touched:**
- `modules/mining/mining.nix` — rewritten (xmrig only, then xmrig stripped)
- `modules/system/sops-secrets-registry.nix` — xmrig secret entries stripped (may need syntax fix)
- `modules/services/monitoring/grafana.nix`, `modules/services/mining-exporter.nix` (deleted)
- `modules/services/k3s-cluster.nix`, `modules/services/syncthing.nix`
- `modules/system/agenix-secrets-registry.nix`, `secrets.nix`, `overlay.nix`
- `kubernetes/`, `containers/`, `packages/`, `pkgs/` — xmrig files deleted
- `modules/gaming/gaming.nix`, `modules/services/monitoring/dashboards/lib.nix`
- `modules/compute-market/default.nix` — mining services default changed
- All caveman/cavecrew locations (OpenCode, Claude, Grok, Skillclaw, etc.)
