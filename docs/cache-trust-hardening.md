# Cache trust hardening

**Status:** staged preparation; no host activation in this change

## Changes in this workstream

- `modules/system/nix-cache-registry.nix` is the single declarative registry
  for cluster substituters and trusted public keys.
- `accept-flake-config` is disabled so a fetched flake cannot silently alter the
  daemon trust boundary.
- Wildcard `trusted-users` are removed from distributed-build configuration.
- NixOS assertions reject automatic flake configuration and wildcard daemon
  trust during host evaluation.

## Signature-enforcement gate

`require-sigs` remains explicitly disabled for now. This is intentional: the
live cluster has a mixed cache state, Sentry is currently unreachable, and the
live Nexus cache advertises a different cache key from the repository's
Zephyr-owned LAN cache. A single Zephyr narinfo was observed with a valid-looking
`zephyr-cache-1` signature, but that does not prove all configured cache paths
and all host builders are compatible.

Before a follow-up changes `require-sigs` to `true`, verify all of the following
from a clean checkout without activating hosts:

1. The canonical cache owner, endpoint, and public key are agreed and rendered
   identically for all four host evaluations.
2. A representative closure path from each configured cache has a valid narinfo
   signature accepted by the declared public-key set.
3. An unsigned or mismatched substitute is rejected and the build falls back to
   a local/remote builder as intended.
4. The rescue build path includes the same trusted key registry and remains able
   to build when the LAN cache is offline.
5. Nexus, Zephyr, Forge, and recovered Sentry each pass effective-config checks.

Do not bypass this gate by re-enabling unsigned substitutes globally. If the
internal cache is retired, remove its endpoint and key from the registry in a
separate, reviewed change.
