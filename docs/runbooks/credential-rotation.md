# Credential Rotation Runbook

**Status:** Canonical operator runbook
**Scope:** Zephyr, Nexus, Forge, Sentry
**Last verified:** 2026-08-16
**Owner:** Cluster operations

This runbook covers rotation of the cluster SOPS age identities and the
external credentials that the 2026-08-16 public-flip security audit found in
the git tree and history. Rotation is mandatory: deletion and history rewrite
cannot revoke a value that was already committed, so every leaked credential
must be rotated at its issuer before the repo goes public.

> The list of leaked values is in `docs/reference/known-issues.md` (audit
> findings section) and in `agents/skills/secrets.md`. Values are never
> reproduced here.

## Order of operations

Rotate the age identity **first**. It is the decrypt key for the whole sops
store, so everything downstream of sops (Casdoor client secret, Samsung TV
token, GHCR token, k3s secrets, etc.) can only be re-sealed safely once the
new age keys exist.

## 1. Rotate the SOPS age identities

Current recipients (`.sops.yaml`): `cluster_age`, `zephyr_age_v2`,
`yubikey_nano`, `yubikey_nfc`. The two YubiKey recipients are **not**
compromised and stay. `cluster_age` and `zephyr_age_v2` were both committed in
plaintext to `hosts/forge/configuration.nix` and must be replaced.

```bash
# On the operator host (zephyr), generate two fresh keypairs.
age-keygen -o ~/.config/sops/age/cluster_age_v3.txt
age-keygen -o ~/.config/sops/age/zephyr_age_v3.txt
```

1. Edit `.sops.yaml`: replace the `cluster_age` and `zephyr_age_v2` public
   keys with the two new public keys. Keep both YubiKey anchors.
2. Re-encrypt the entire store with the new recipient set:

   ```bash
   # sops -r re-encrypts each file's data key to the current .sops.yaml
   # recipients. updatekeys drops recipients that are no longer listed.
   find secrets -name '*.yaml' -exec sops updatekeys --config .sops.yaml -y {} \;
   ```

3. Verify every file still decrypts with the new key and that no file
   references the old fingerprints:

   ```bash
   find secrets -name '*.yaml' -exec sops --config .sops.yaml -d {} \; >/dev/null
   ```

4. Seed the new private keys onto the hosts (never through git):

   | Host | Key file path | Source |
   |------|---------------|--------|
   | zephyr | `~/.config/sops/age/keys-combined.txt` | both new private keys |
   | nexus | `/persistent/etc/nixos/.age/key.txt` | both new private keys |
   | sentry | `/persistent/etc/nixos/.age/key.txt` | both new private keys |
   | forge | `/persistent/etc/sops/age/key.txt` | both new private keys |

   The file must contain **both** private keys (sops files are encrypted to
   multiple recipients; a host may need either to decrypt). `age-keygen` output
   is concatenated into one file.

5. Deploy and confirm `secretspec-creds` resolves cleanly on every host
   (`journalctl -u secretspec-creds`), then delete the old private keys
   (`cluster_age` + `zephyr_age_v2`) from every host and from
   `~/.config/sops/age/`.

## 2. Rotate external credentials

Rotate each value at its issuer, then re-seal the new value into the sops
store (or the issuer-managed path it is provisioned from). Redact on rotation;
do not commit new values in plaintext.

| Credential | Where it leaked | Re-seal into |
|------------|-----------------|--------------|
| CONTEXT7 API key | `env-vars`, history | `secrets/ai/context7-api-key.yaml` |
| Gemini (deleted 2026-08-16 — key removed at Google AI Studio; no sops secret entry exists; all config references removed) API key | `env-vars`, history | `secrets/ai/gemini-api-key.yaml` |
| Hugging Face token | `env-vars` | `secrets/ai/huggingface-token.yaml` (or issuer token) |
| GHCR PAT | history (`a727b420`) | issuer-issued; store via secretspec if still used |
| Casdoor admin/client secret | `secrets/casdoor/mcp-gateway-credentials.env` | `secrets/k8s/casdoor-*.yaml` |
| Samsung TV token | `.secretspec.env` | sops entry backing `SAMSUNG_TV_TOKEN` |
| Akash provider keys | history (`c1435677`) | issuer-issued |
| Hermes / OpenCode / ZAI keys | history (multiple commits) | `secrets/ai/*.yaml` |

For sops-backed values, edit the plaintext in-place with the operator key:

```bash
sops --config .sops.yaml secrets/ai/context7-api-key.yaml
```

## 3. Post-rotation checklist

- [ ] `sops updatekeys` ran over every `secrets/*.yaml`; old fingerprints gone
- [ ] `find secrets -name '*.yaml' -exec sops -d {} \;` succeeds with the new key
- [ ] New private keys seeded on all four hosts at the paths above
- [ ] Old private keys deleted from every host and the operator machine
- [ ] Every leaked external credential rotated at its issuer and re-sealed
- [ ] `just secretspec-check` passes
- [ ] History rewrite (or fresh public snapshot) completed before flipping public
- [ ] A secret-scanning gate (gitleaks/trufflehog) is added to pre-commit + CI
