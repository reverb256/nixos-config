# HEY.md — Cross-Agent Coordination

**Purpose:** Shared scope coordination for multiple AI agents (different
sessions, models, or vendors). Read this before working. Update when done.

**Last updated:** 2026-08-05 (UTC-5)

---

## Active Sessions

| Agent | Scope | Files/hosts touched | Off-limits | Status | Last active |
|-------|-------|---------------------|------------|--------|------------|
| j_kro-systemd_recovery | Sentry crash investigation + cluster k3s recovery | modules/system/kernel-hardening.nix, hosts/sentry/configuration.nix, hosts/sentry/services.nix, hosts/forge/services.nix, modules/development/ai-coding-tools/droid.nix, modules/system/sops-secrets-registry.nix | Peakminer/mining services, MapleSpike, Niri desktop configs | ✅ Cluster restored (nexus+forge+sentry); ✅ etcd quorum fixed (identity-only encryption); ✅ Forge agent config committed; ✅ Sentry panic=30 config committed; 🔄 Sentry k3s still cycling (3-member etcd formed, k3s not fully becoming Ready) | 2026-07-21 05:05 (UTC-5) |
| j_kro-boot-debug | Boot journal review on zephyr (gen 2283) + cluster wide pre-deploy fix | hosts/zephyr/configuration.nix, hosts/zephyr/monitoring.nix, hosts/forge/configuration.nix, hosts/forge/monitoring.nix, modules/services/hermes-cli.nix, modules/system/home-manager.nix, modules/system/systemd-user-timeout.nix, modules/system/users.nix | MapleSpike, k3s cluster topology | ✅ Issue #300 created; ✅ Worktree issue-300-boot-debug-remediation; ✅ Commit 90949f9 pushed to origin + central; ✅ PR #301 opened (`fix(boot): repair syntax-broken zephyr config + 5 deprecation drift issues`); ✅ `nix eval` clean on all 4 hosts; 🔄 Awaiting PR review + merge; 🔄 Post-merge `just deploy zephyr` first | 2026-07-21 20:43 (UTC-5) |

(Stale prior sessions archived — nexus-dns-and-hermes, maplespike-24-issues, nexus-de-vm-boot, infra/dns-recovery, quill-portal-fixes were all ✅ Done from earlier sessions.)

| D8 | `home-manager-config` is a pinned flake input; `modules/home-manager/` deleted | Both repos advance via flake lock; single source of truth is `reverb256/home-manager-config` | j_kro | 2026-08-05 |
---

## Active Decisions

| ID | Decision | Rationale | Agent | Date |
|----|----------|-----------|-------|------|
| D1 | Use `git+https://` not `github:` for flake inputs | curl-42 abort on tarball API (api.github.com) | j_kro | 2026-07-15 |
| D2 | Remove `--substitute-on-destination` from post-build-hook | Truncated nars cached as valid paths (NixOS/nix#2389) | j_kro | 2026-07-15 |
| D3 | Builders: nexus+sentry only — no forge (mining), no krash3 (Windows) | Builds compete with mining; krash3 is Windows-only | j_kro | 2026-07-15 |
| D4 | Remove `http://10.1.1.120:50000` from substituters declaratively | nix-serve served truncated nars from corrupted store | j_kro | 2026-07-15 |
| D5 | Build locally with `--impure` for freebuff-desktop | AppImage path access forbidden in pure eval (pre-existing) | j_kro | 2026-07-15 |
| D6 | Remove boot-time VFIO module loading on nexus; VFIO loads on demand | GPU boots on nvidia for AI inference; VFIO loaded by handoff script at VM start | j_kro | 2026-08-16 |
| D7 | home-manager-config is a pinned flake input; local `modules/home-manager/` deleted | Both repos advance via flake lock; single source of truth is `reverb256/home-manager-config` | j_kro | 2026-08-05 |
