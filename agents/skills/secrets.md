# Working with cluster secrets

**Last verified:** 2026-08-16

Two paths run in parallel. SecretSpec is the declarative runtime schema and
validation layer; sops-nix remains a compatibility path.

## File locations

| File | Purpose |
|------|---------|
| `secretspec.toml` | Source of truth for declared secrets and `ref` routing |
| `.env.secrets` | Local dotenv values for env-backed secrets (keep real values out of git) |
| `secrets/` | Encrypted sops material referenced by the schema |
| `~/.config/sops/age/keys-combined.txt` | Zephyr operator age identities |
| `/persistent/etc/nixos/.age/key.txt` | nexus/sentry age key (preservation-persisted) |
| `/persistent/etc/sops/age/key.txt` | forge age key (preservation-persisted) |

## Rotating credentials

Full procedure: `docs/runbooks/credential-rotation.md`. The age identity is
rotated first (it gates the whole sops store), then each leaked external
credential. Never commit a private age key to the nix config — the
2026-08-16 audit found the previous forge `pkgs.writeText` copy had leaked both
private keys into history.

## Sops-backed entries

Entries in `secretspec.toml` route sops decryption with a `ref`:

```toml
NVIDIA_API_KEY = { required = true, type = "password",
  ref = { item = "ai/nvidia-api-key.yaml#data" } }
```

`item` is `<file-under-secrets/>#<yaml-key>`.

## Validate

```bash
just secretspec-check    # resolve all required secrets with the production profile
just secretspec-list     # list the declared schema keys
```

Never edit `/run/secrets/` directly. Never put plaintext values in documentation.

## Gotchas

- `nix build` for the secretspec forks needs `--option pure-eval false`.
- `secretspec-validate-local` runs an ephemeral age-keypair end-to-end test.
- `secrets/infra/ssh-ca-key.yaml` is the canonical SSH CA; host certs are re-signed
  on boot by `ssh-host-cert-sign.service`.
