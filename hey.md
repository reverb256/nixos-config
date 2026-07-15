# hey.md — cross-agent coordination (NixOS homelab /etc/nixos)

**Purpose:** lightweight scope coordination so parallel agents don't collide on
the same hosts, modules, or generations. Update your section when you start/finish.

## Agent: nexus-dns-and-hermes (this session — j_kro)
- **Scope DONE:**
  - Hermes config: `model: glm-5-turbo` fixed → proper mapping (no zai/glm-5).
  - `modules/network/cluster-dns.nix`: `lan. transparent` for CDI short-name DNS.
  - `modules/system/home-manager.nix`: niri gated to zephyr/sentry.
  - **`modules/services/k3s-cluster.nix`**: removed broken `--flannel-conf` approach,
    replaced with `--flannel-backend=${cfg.flannelBackend}`. Removed flannel.conf
    environment.etc generation. Commit `ddde68cf` on `origin/main`.
  - Deploy `proc_62de33ece94e` running on nexus via non-git nixos-rebuild.
- **Off-limits respected:** forge/peakminer, forge/services, sentry/services,
  niri-config untouched.

## Agent: nexus-de-vm-boot (this session)
- **Scope (original):** Fix nexus↔krash3 cross-node pod routing and boot nexus-de VM.
- **Status:** k3s-cluster.nix fix committed. Nexus deploying with `--flannel-backend=host-gw`.
  After deploy: clear flannel annotations + restart k3s. Then repeat for krash3.
  REMOVED: flannel.conf machinery (was broken; use --flannel-backend directly).

## Agent: infra/dns-recovery (this session)
- **Status:** HOLDING until host-gw harmonization lands. 4 fix commits on main.

## Agent: flake-281-verify (this session) — DONE
## Agent: garnix-removal (this session) — DONE

## Agent: maplespike-24-issues (this session — j_kro)
- **Scope:** 24 MapleSpike production issues across quill repo + nixos-config.
  quill repo at ~/Projects/quill.
- **Status:**
  - ✅ All 24 issues implemented, committed, pushed (13 quill commits + 4 nixos-config commits)
  - ✅ Lockfile updated, Dockerfiles created, tsconfig paths fixed
  - ✅ Container images built from cached Nix store + pushed to nexus:5000
  - ✅ Rollout complete — quill-api/mcp/portal running across forge+sentry+nexus (pinned digests)
  - ✅ Bonsai 27B deployment — PrismML fork built, models downloaded (ternary + 1-bit)
  - ⏳ Building llama.cpp with CUDA (tmux prism-build on zephyr) for native Nix integration
  - ⏳ Will deploy as systemd services replacing current llama-server endpoints
- **Not touched:** k3s-cluster.nix, flannel config, DNS, forge/sentry services, niri-config,
  flake.lock, hermes config, knowledge-fabric-mcp, krash3/krash3-vm

## Agent: knowledge-fabric-mcp (this session)
  (Qdrant, SearXNG, code search, brain wiki). Extracted from
  ai-inference-gateway middleware. Code at ~/knowledge-fabric-mcp
  (github.com/reverb256/knowledge-fabric-mcp). Systemd service on nexus.
- **Status:** Code committed. Deploy script ready. NOT deployed (waiting
  on user approval for nexus deploy).
- **Not touched:** forge/*, sentry/*, niri-config, k3s-cluster, flake.lock.
