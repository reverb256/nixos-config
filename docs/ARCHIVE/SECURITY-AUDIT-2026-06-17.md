---
last-verified: 2026-06-17
verified-by: Hermes Agent
verification-method: security audit
expires: 2026-07-01
---

# Security Audit — 2026-06-17

**Scope:** /etc/nixos NixOS flake configuration repository
**Host:** zephyr (NixOS 26.11)
**Cluster:** 4-node (zephyr, nexus, forge, sentry) + WSL (krash3)

## Findings

### Critical
1. **env-vars tracked in git** -- contained live API keys (Anthropic, ZAI, Gemini, Context7)
2. **secrets/context7/api-key.age** -- plaintext Context7 key with misleading .age extension
3. **secrets/casdoor/mcp-gateway-credentials.env** -- plaintext Casdoor SSO passwords

### High
4. SSH key lived inside repo dir at `/etc/nixos/ssh/id_ed25519` (gitignored, but same tree)
5. Age key at `/etc/nixos/.age/key.txt` in repo working tree (gitignored, 600 perms)
6. `nohup.out` (2MB) and `records/` (326KB conversations) in repo

### Medium
7. Firewall exposes many ports on workstation (NFS, k3s, llama-server, miners)
8. Pre-commit hooks had no secret scanning
9. `.gitignore` missing `env-vars`, `.env`, `secrets/*.env` patterns
10. Backup files (.bak, .backup) scattered in repo

## Remediation Applied (Commit f4fac906)

### Structural Fixes
- Removed 4 tracked plaintext secret files from git
- Moved SSH key references from `/etc/nixos/ssh/` to `~/.ssh/id_ed25519`
- Deleted working tree garbage (nohup.out, records/, 7 .bak files, 3 stale .age.bak files)
- Hardened `.gitignore` with comprehensive secret pattern coverage
- Added `gitleaks protect --staged` pre-commit hook
- Reviewed firewall -- NFS properly interface-restricted, existing hardening adequate

### Files Removed from Tracking
| File | Reason |
|------|--------|
| env-vars | Live API keys |
| .env | Environment file |
| secrets/casdoor/mcp-gateway-credentials.env | Plaintext Casdoor SSO |
| secrets/context7/api-key.age | Plaintext Context7 key |
| secrets/context7-api-key.age.bak2/bak3 | Stale key backups |
| nohup.out | 2MB log artifact |
| records/* | Conversation logs |

### Still Needed (after key rotation)
1. Rotate all exposed credentials
2. `git filter-repo --path env-vars --path .env --path secrets/context7/api-key.age --path secrets/casdoor/mcp-gateway-credentials.env --invert-paths`
3. Force push to origin, central, gitea remotes
4. Coordinate with collaborators to re-clone

## Files to Never Commit
- `env-vars`
- `.env`
- `secrets/*.env`
- `nohup.out`
- `records/`
- `*.bak`, `*.backup`, `*.rej`, `*.orig`
- Any `.txt` file under `secrets/`
