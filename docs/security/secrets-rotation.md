# Secrets Rotation Procedures

## Overview

This document describes procedures for rotating encrypted secrets managed by Agenix.

## Rotation Procedure

### Step 1: Generate new secret value

```bash
# Example: generate new API key
openssl rand -base64 32
```

### Step 2: Re-encrypt with Agenix

```bash
# Edit the secret file
agenix -e secrets/huggingface-token.age --edit
# Replace with new value, save
```

### Step 3: Rebuild and deploy

```bash
just deploy
```

### Step 4: Verify new secret is in use

```bash
# Check service logs for authentication success
journalctl -u <service-name> -f
```

### Step 5: Invalidate old secret (if applicable)

- Revoke old API key via provider dashboard
- Delete old credentials from external systems

## Rotation Schedule

| Secret | Rotation Period | Last Rotated | Next Due |
|--------|----------------|--------------|----------|
| Hugging Face token | 90 days | TBD | TBD |
| LM Studio API key | 90 days | TBD | TBD |
| ZAI API key | 90 days | TBD | TBD |
| Grafana admin password | 180 days | TBD | TBD |
| Tailscale API key | 90 days | TBD | TBD |

## Automating Rotation

Future enhancement: Use GitHub Actions to:
1. Generate new secrets
2. Re-encrypt with Agenix
3. Open PR for rotation
4. Deploy after approval

## References

- https://github.com/ryantm/agenix
- https://owasp.org/Top10/A07_2021-Identification_and_Authentication_Failures/
