---
last-verified: 2026-06-12
verified-by: Sisyphus
verification-method: just docs-audit
expires: 2026-06-19
---
# Architecture

See INFRASTRUCTURE-AUDIT.md for current state.

**Core Tenets:**
- Nexus (46GB) is default workload node
- Zephyr is source of truth (NFS export)
- All AI traffic goes through AI Gateway on Nexus
- Central SSO via Casdoor + oauth2-proxy + Caddy forward_auth
- Documentation in docs/LIVE/ is canonical

Full diagrams to be added.
