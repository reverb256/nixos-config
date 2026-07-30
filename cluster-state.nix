# cluster-state.nix — Static source-of-truth for STATUS.md non-dynamic sections.
#
# Why this lives as a Nix expression (not YAML/Markdown):
#   * `secretspec check` and other upstream tools already depend on the
#     the Nix toolchain (Haskell/Rust evaluators with `--json` output),
#     so there's no new tool dependency.
#   * Future cluster validators (e.g. "does STATUS.md drift from this
#     spec?") can read this SAME JSON via the same interpreter.
#   * The top-level attrset is a valid Nix expression, so `nix-instantiate
#     --parse` validates syntax and `nix eval --json --file` serializes
#     without a build step.
#
# Data model:
#   * components — Cluster Health Overview table rows (Kubernetes, control plane, etc.).
#   * nodes      — Per-node static facts (GPU counts, GPU model, vendor capabilities).
#   * phases     — K8s migration phase table (Phase 1..7).
#   * known_issues — Known issues list with date stamping.
#   * notes      — Inline meta-notes rendered as `> ` blockquote lines.
#   * overall_progress / overall_progress_label — Top-of-section headline.
#
# Dynamic sections (cluster pod counts, resource usage, last-updated
# timestamp) stay in `scripts/update-status.sh` because they depend on
# kubectl which has no offline equivalent. When this file changes, the
# next regen produces a draft-updated STATUS.md; commit review of the
# diff is the same as for a NixOS module change.
#
# Editing convention: bump `last_updated` whenever you change a value so
# a stale cached JSON render can't go unnoticed.
{
  last_updated = "2026-07-24";

  overall_progress = "✅ **95% COMPLETE**";
  overall_progress_label = "All 7 phases finished, known issues remain";

  # ── Cluster Health Overview ──────────────────────────────────────────
  components = [
    { emoji = "🟢 RUNNING";       name = "Kubernetes";         details = "v1.35.0, 4 nodes joined"; }
    { emoji = "🟢 OPERATIONAL";   name = "Control Plane";      details = "Zephyr: apiserver, etcd, scheduler, controller-manager"; }
    { emoji = "🟢 4/4 READY";     name = "Worker Nodes";       details = "Zephyr, Nexus, Sentry, Forge"; }
    { emoji = "🟢 OPERATIONAL";   name = "Networking";         details = "CNI, CoreDNS, Unbound cluster DNS"; }
    { emoji = "🟢 DEPLOYED";      name = "Ingress Controller"; details = "Caddy Ingress (DaemonSet on 2 nodes)"; }
    { emoji = "🟢 PARTIAL";       name = "GPU Passthrough";    details = "Zephyr: 2x NVIDIA (✓), Forge: 2x AMD + 2x NVIDIA (⚠️)"; }
    { emoji = "🟢 RUNNING";       name = "Monitoring";         details = "Prometheus, Grafana, AlertManager, node-exporters, Caddy metrics"; }
    { emoji = "🟢 OPERATIONAL";   name = "Storage";            details = "NFS shared storage, local-path provisioner"; }
    { emoji = "🟢 DEPLOYED";      name = "GPU Marketplace";    details = "Auction engine coordinating mining/K8s/gaming"; }
  ];

  # ── GPU Resources by Node ───────────────────────────────────────────
  # `cuda`/`rocm`/`vulkan` are booleans; renderer scripts convert to ✅/-.
  nodes = [
    { name = "Zephyr"; nvidia = "2 (RTX 3090 + 3060 Ti)"; amd = "0";          cuda = true;  rocm = false; vulkan = true;  }
    { name = "Nexus";  nvidia = "1 (RTX 3060 Ti)";         amd = "0";          cuda = true;  rocm = false; vulkan = true;  }
    { name = "Forge";  nvidia = "2 (RTX 4060)";            amd = "2 (RX 5700 XT)"; cuda = true;  rocm = true;  vulkan = true;  }
    { name = "Sentry"; nvidia = "0";                       amd = "1 (RX 5600 XT)"; cuda = false; rocm = true;  vulkan = true;  }
  ];

  # ── Migration Progress ──────────────────────────────────────────────
  phases = [
    { status = "✅ COMPLETE"; name = "Phase 1: Foundation";        completion = "100%"; notes = "Control plane, networking, CoreDNS"; }
    { status = "✅ COMPLETE"; name = "Phase 2: Worker Nodes";      completion = "100%"; notes = "All nodes joined, correct CIDRs, DNS functional"; }
    { status = "✅ COMPLETE"; name = "Phase 3: Stateful Services"; completion = "95%";  notes = "**GlitchTip PostgreSQL migrated** (2026-03-19)"; }
    { status = "✅ COMPLETE"; name = "Phase 4: Stateless Services"; completion = "95%"; notes = "**GlitchTip web/worker/redis migrated** (2026-03-19), Caddy Ingress, n8n, home-assistant"; }
    { status = "✅ COMPLETE"; name = "Phase 5: GPU Workloads";     completion = "95%";  notes = "**llama.cpp deployed, Gateway integrated, tested** (2026-03-19)"; }
    { status = "✅ COMPLETE"; name = "Phase 6: Monitoring";        completion = "100%"; notes = "Prometheus + Grafana running, **Caddy metrics configured**"; }
    { status = "✅ COMPLETE"; name = "Phase 7: Cleanup";           completion = "95%";  notes = "**Removed obsolete manifests, finalized documentation** (2026-03-19)"; }
  ];

  # ── Known issues (rendered as a bullet list) ────────────────────────
  known_issues = [
    { emoji = "⚠️"; name = "Monitor brightness"; description = "ASUS/Acer displays not controllable via Plasma slider (EDID limitation, hardware workaround required)"; date = "2026-03-21"; }
    { emoji = "⚠️"; name = "Gaming detection"; description = "Using Volcano scheduler instead of YuniKorn (migration completed, docs need update)";      date = "2026-03-21"; }
  ];

  # ── Inline meta-notes (rendered as `> ` blockquote lines) ───────────
  notes = [
    "Node ages reflect CIDR fix + role label application. Roles describe node function for pod scheduling."
    "etcd HA cluster (zephyr, nexus, sentry) remains unchanged from original setup."
    "**Note (2026-03-16):** CUDA issue resolved by removing `allowUnsupportedSystem = true;` from flake.nix. See `docs/CUDA_TROUBLESHOOTING.md` for details."
  ];
}
