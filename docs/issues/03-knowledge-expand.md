# Issue #3: knowledge.md "Other services" expansion

**Priority:** LOW  
**Status:** Open  
**Created:** 2026-07-25  
**Origin:** Drift cycle appended section to knowledge.md but the existing "Other services" section (gitea, vaultwarden, n8n, garage, searxng) is empty / under-documented  
**Depends on:** none  
**Blocks:** contributor onboarding

## Context

`knowledge.md` already has the "Internal services" section at the top listing Casdoor/oauth2-proxy/Garage/Vaultwarden/AI/dev/observability categories. The "Quickstart" + "Architecture" sections are comprehensive. But "Other services" (mentioned in the existing structure) doesn't list detailed per-service routing (which port, which namespace, which sanity-check command, which common failure mode). New operators looking to investigate vaultwarden issues have to grep `modules/services/vaultwarden-module.nix` + K8s manifests manually.

## Acceptance Criteria

- Each "Other service" (gitea, vaultwarden, n8n, garage, searxng) gets a 3-5 line entry covering: port/NodePort, namespace/host, common sanity-check (`just <recipe>`), one-line troubleshooting pointer.

## Approach

1. Read existing `knowledge.md` "Internal services" + "Other services" to understand the current shape.
2. Read `kubernetes/service-ports.nix` + relevant host/service modules for accurate port/namespace data.
3. Add the 3-5 line entries inline. Preserve existing structure.
4. Verify the new content shows in `rg -n 'gitea|vaultwarden' /etc/nixos/knowledge.md`.

## Related

- `kubernetes/service-ports.nix`
- `knowledge.md`
