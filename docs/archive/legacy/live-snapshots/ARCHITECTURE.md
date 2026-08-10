---
last-verified: 2026-07-30
verified-by: Buffy
verification-method: source inspection of flake.nix, colmena.nix, justfile, and dispatcher
expires: 2026-08-06
---
# Architecture

See INFRASTRUCTURE-AUDIT.md for current state.

**Core Tenets:**
- Nexus (46GB) is default workload node
- Zephyr is the authoring/source-of-truth host; Nexus is the build/deployment dispatcher
- All AI traffic goes through AI Gateway on Nexus
- Central SSO via Casdoor + oauth2-proxy + Caddy forward_auth
- Documentation in docs/LIVE/ is canonical

Full diagrams to be added.
