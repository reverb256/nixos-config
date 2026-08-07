# Buzz Deployment — Cluster Plan (2026-08-07)

Lightweight, current-state deployment notes for Jack Dorsey / Block's Buzz
(`github.com/block/buzz`, Apache 2.0) on this homelab. Companion to the
`buzz-field-evaluation` and `buzz-hermes-integration` skills.

## Upstream reality (verified 2026-08-07)

- Desktop **v0.5.6** (108 releases, 2.2k commits, 100 contributors, 24.9k★).
  Far past the "1-week beta" launch framing.
- Works: relay, channels/threads/DMs, canvases, media, search, audit log,
  Desktop app, `buzz-cli`, ACP harness (Goose/Codex/Claude Code), YAML
  workflows, NIP-34 git events.
- WIP: mobile clients, workflow approval gates (glue drying), huddle lifecycle.
- Stack: one Rust binary (`buzz-relay`) + **Postgres 17, Redis 7, MinIO (S3)** +
  optional Caddy/TLS. Docker-only (no Nix derivation).

## Node strategy (nexus down 2026-08-07)

- **zephyr** — lightweight/surface/control-plane: Buzz Desktop client, Caddy
  `wss://buzz.<domain>` proxy, `buzz-acp`/`buzz-cli` harness, DNS. NO DB tier
  (31GB, constant OOM risk).
- **sentry** — backend/heavy: the relay Docker stack (Postgres/Redis/MinIO) +
  Caddy TLS. 31GB, not mining-critical. Use `forge` only if Sentry needed for
  Vulkan inference.
- **nexus** — return here when back (46GB, was builder/dispatcher); long-term
  home for the relay stack; migrate compose stack, Sentry hands off.

## Critical gotchas

- `RELAY_URL` = the community key. Set to exact `wss://` URL (host+port+scheme)
  clients use, BEFORE adding data. Change later = fresh empty community. Use
  `127.0.0.1` not `localhost` locally (agents canonicalize).
- Two keys: `BUZZ_RELAY_PRIVATE_KEY` (relay identity, unrotatable) +
  `RELAY_OWNER_PUBKEY` (your account, unremovable). Back both up in sops-nix.
- Use production `deploy/compose/` bundle, NOT root `docker-compose.yml` (dev).
- Pin `BUZZ_IMAGE` to a release tag/digest once data matters.
- Mosaic's `mosaic-bridge-buzz` points at `wss://relay.damus.io` (public Nostr
  relay) — it is NOT a self-hosted Buzz relay; don't conflate.

## Hermes wiring

Hermes has ACP support (`hermes acp`); Buzz's `buzz-acp` can spawn it like any
harness. See `buzz-hermes-integration` skill for the quality-controller pattern.
