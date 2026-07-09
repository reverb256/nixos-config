# SOPS-NIX — secrets management

> **TL;DR.** sops-nix is wired into `/etc/nixos/common-modules-list.nix`.
> The registry module `modules/system/sops-secrets-registry.nix` (560 lines)
> declares secrets behind per-host feature flags, gated by a master
> `services.sops-secrets-registry.enable` (default: `false`). As of the
> 2026-07-08 migration
> (`zephyr: enable sops-secrets-registry; migrate Hermes creds to sops-nix`)
> **`zephyr` sets `enable = true`** with feature flags scoped to
> `aiServices`, `kubernetes`, `cloud`, `storage`, `mining`, `automation`,
> `ci`, and `selfHosting` (`monitoring = false`). This resolves **89
> secrets** on zephyr and `nixos-rebuild switch` now decrypts them at
> activation. The Hermes bootstrap credential set (`nvidia`,
> `opencode`/zen, `opencode-go`, `zai`, `casdoor-hermes-jwt`) and the
> re-keyed `ai/telegram-bot-token` decrypt successfully with zephyr's age
> key; the other four hosts (`forge`, `nexus`, `sentry`, `krash3`) remain
> at the default `enable = false`. The historical 0/135 legacy-files
> decrypt mismatch is **still real** for any secret file that was NOT
> re-encrypted under the zephyr-only `.sops.yaml` policy — see the warning
> block under `## Hermes bootstrap credentials via sops-nix`. Do NOT assume
> all 135 secrets decrypt; only the set currently enabled on zephyr (and
> re-keyed to zephyr's pubkey) does.

## Current state

- **Module wiring:** `common-modules-list.nix` line 8
  (`inputs.sops-nix.nixosModules.default`) + line 9 (`./modules/system/sops-secrets-registry.nix`).
- **Hosts:** `forge`, `nexus`, `sentry`, `zephyr`, `krash3` (defined at
  `flake.nix:260`; assembled via `mkNixosSystem` at `flake.nix:284`).
- **Per-host flags:** `zephyr` is the only host with the registry enabled.
  As of 2026-07-08 it sets `services.sops-secrets-registry.enable = true`
  with `aiServices`, `kubernetes`, `cloud`, `storage`, `mining`,
  `automation`, `ci`, `selfHosting` = `true` and `monitoring = false`
  (in `hosts/zephyr/services.nix`). The other four hosts (`forge`,
  `nexus`, `sentry`, `krash3`) stay at the default `enable = false`, so
  the registry `mkIf` block remains inert there. Concretely on zephyr:
  - `nix eval ...#nixosConfigurations.zephyr.config.sops.age.keyFile`
    returns `"/etc/nixos/.age/key.txt"`.
  - `nix eval ...#nixosConfigurations.zephyr.config.sops.secrets
    --apply 'x: builtins.attrNames x'` returns **89 secret names**
    (the full enabled set across the 8 active feature flags).
- **Canonical recipient:** `/etc/nixos/.sops.yaml` (git-tracked,
  uncommitted) lists **one** recipient:
  `age1p98yp8w64rdugp03332gxnz5v2vcnucn69cs5qm6s2l2u7epqfcqmu2pqe` —
  identical to `/home/j_kro/.age/key.txt`. Newly-encrypted secrets will
  therefore decrypt on `zephyr` once any host enables the registry.
- **Pre-policy legacy (re-keyed subset on zephyr):** the 64 top-level
  `*.age` files + ~71 subdir `*.yaml`/`*.env.yaml` files were originally
  encrypted to historical recipient sets that did NOT include `zephyr`'s
  pubkey. During the 2026-07-08 migration the subset zephyr actually
  enables was re-keyed to zephyr's pubkey and now decrypts via sops-nix
  at activation. The remaining unreferenced/legacy files still decrypt
  0/N locally with the local key and remain out of scope until
  explicitly re-encrypted under `.sops.yaml`. Treatment: re-key with
  `sops ... --encrypt --in-place` (uses `.sops.yaml` `creation_rules`,
  which enrolls zephyr's pubkey) if/when actually needed; otherwise
  leave untouched.

## Key file location & resync

When the registry IS enabled on a host, it sets (via the `mkIf` block):

```nix
sops.age.keyFile = "/etc/nixos/.age/key.txt";
```

Because that block is gated, today no host's `eval` resolves this
attribute; the value persists in the registry module and the canonical
key file is preserved regardless of activation state.

| Path                          | Owner       | Mode | File-system role                 |
|-------------------------------|-------------|------|----------------------------------|
| `/etc/nixos/.age/key.txt`     | root:root   | 0600 | What the registry cites on hosts where `services.sops-secrets-registry.enable = true` |
| `/home/j_kro/.age/key.txt`    | j_kro:users | 0600 | Source-of-truth user copy; used by `sops` CLI directly |

The two MUST stay byte-identical. After any `sops updatekeys` /
`age-keygen`, sync:

```bash
sudo cp ~/.age/key.txt /etc/nixos/.age/key.txt
sudo chown root:root /etc/nixos/.age/key.txt
sudo chmod 600 /etc/nixos/.age/key.txt
```

A NixOS activation script that warns on divergence is NOT installed —
the manual resync above is the current contract. The earlier redundant
`/etc/sops/age/keys.txt` was decommissioned; the explicit `sops.age.keyFile`
makes the sops-nix default-fallback path moot.

## Registry module quick reference

File: `/etc/nixos/modules/system/sops-secrets-registry.nix` (569 lines).

Shape (confirmed by inspection of the file):

```nix
{ config, lib, inputs, ... }: let inherit (lib) mkOption types mkIf; in {
  options.services.sops-secrets-registry = {
    enable      = mkOption { ... };   # master toggle
    aiServices  = mkOption { ... };   # feature flags
    kubernetes  = mkOption { ... };
    cloud       = mkOption { ... };
    monitoring  = mkOption { ... };
    mining      = mkOption { ... };
    storage     = mkOption { ... };
    automation  = mkOption { ... };
    selfHosting = mkOption { ... };
    ci          = mkOption { ... };
    # ... (see file for the full list)
  };
  config = mkIf config.services.sops-secrets-registry.enable {
    sops = {
      defaultSopsFile   = "${inputs.self}/secrets/ai/nvidia-api-key.yaml";
      defaultSopsFormat = "binary";
      age.keyFile       = "/etc/nixos/.age/key.txt";
    };
    # The remaining body is a flat sops.secrets.<name> = { ... }; attrset,
    # gated per feature. Open the file directly to see the exact wiring
    # for each secret — the structure has evolved over time.
  };
}
```

**Do not assume a specific combinatorial pattern** (e.g., `mkMerge`,
`mkIf`-lists, or `with` magic). The body of the registry is plain Nix
attribute-set literals, with `mkOption`-typed options for feature flags.
For each secret that should be decrypted on a host, set the relevant
feature flag in that host's `configuration.nix`.

## Hermes bootstrap credentials via sops-nix

The NixOS deployment is now the **canonical secret source for Hermes'
bootstrap credentials** on zephyr. This replaced the old `hermes_vault`
secret-source plugin (`secrets.sources` no longer lists `hermes_vault`,
the `secrets.hermes_vault` block is deleted, and `hermes-vault-secret-source`
is removed from `plugins.enabled` in `~/.hermes/config.yaml`). The earlier
`secrets.sources names unknown source(s): hermes_vault` warning is gone.

Flow:

1. **sops-nix decrypts** the credential files into `/run/secrets/` at
   activation (registry `enable = true` on zephyr). The Hermes-relevant
   entries are:
   - `ai/nvidia-api-key` → `/run/secrets/nvidia-api-key`
   - `ai/opencode-api-key` → `/run/secrets/opencode-api-key`
   - `ai/opencode-go-api-key` → `/run/secrets/opencode-go-api-key`
   - `ai/zai-api-key` → `/run/secrets/zai-api-key`
   - `k8s/casdoor-hermes-jwt` → `/run/secrets/casdoor-hermes-jwt`
   - `ai/telegram-bot-token` → `/run/secrets/telegram-bot-token`
     (re-keyed to zephyr's pubkey; `format = "yaml"`, nested
     `ai: { telegram-bot-token: ... }` structure so the
     sops-install-secrets YAML validator finds the key matching the
     manifest name `ai/telegram-bot-token`).
2. **The `hermes-cli` module wires** these paths into Hermes via the
   `*ApiKeyFile` options:
   - `apiKeyFile = "/run/secrets/zai-api-key"`
   - `nvidiaApiKeyFile = "/run/secrets/nvidia-api-key"`
   - `casdoorJwtFile = "/run/secrets/casdoor-hermes-jwt"`
   - `opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key"`
   - `opencodeZenApiKeyFile = "/run/secrets/opencode-api-key"`
   The module also runs a oneshot `systemd.service.hermes-config-secrets`
   that injects the Casdoor JWT into `~/.hermes/config.yaml` (waits up to
   30s for the sops-nix secret to appear) and fixes stale gateway URLs.
3. **Non-Nix creds** still come from `~/.hermes/.env` (hand-maintained,
   plaintext) for anything not yet expressed through a `*ApiKeyFile`
   option (e.g. `kilocodeApiKeyFile`, `geminiApiKeyFile`, `hfTokenFile`,
   `githubTokenFile` are declared in the module but not all are wired in
   `hosts/zephyr/services.nix`).

> **WARNING (scope).** Only the secret set currently **enabled on zephyr**
> (the 8 active feature flags, 89 secrets) and re-keyed to zephyr's pubkey
> decrypts. This is NOT a claim that all 135 historical secret files are
> now valid — the 2026-07-03 mass rekey left many `cloud`/`storage`/
> `mining`/`automation`/`ci`/`selfHosting`/`monitoring` files with the
> wrong sops envelope ("no binary data found in tree"). Those that zephyr
> actually needs were re-keyed as part of the 2026-07-08 migration; any
> others remain latent and out of scope until explicitly re-encrypted under
> `.sops.yaml`. The `monitoring/*` group is the only *declared* group left
> disabled on zephyr (`monitoring = false`).

Each secret entry in the registry looks like:

```nix
"<secret-name>" = {
  sopsFile = "${inputs.self}/secrets/<feature>/<secret-name>.yaml";
  format   = "binary";
  # optional: owner = ".."; mode = "0440"; restartUnits = [ "..." ];
};
```

## Adding a new secret

1. Pick a feature group (`ai`, `k8s`, `cloud`, etc.) + secret name.
2. Create `/etc/nixos/secrets/<feature>/<name>.yaml` with plaintext.
3. Encrypt in-place via the local `.sops.yaml`:

   ```bash
   cd /etc/nixos
   sops --config /etc/nixos/.sops.yaml --encrypt --in-place \
       secrets/<feature>/<name>.yaml
   ```
4. Add a registry entry in `modules/system/sops-secrets-registry.nix`
   inside the `mkIf config.services.sops-secrets-registry.enable` body.
5. Enable the registry + the relevant feature on the target host:

   ```nix
   # hosts/<host>/configuration.nix
   services.sops-secrets-registry.enable       = true;
   services.sops-secrets-registry.<feature>    = true;
   ```
6. Validate without applying:

   ```bash
   sudo nix --extra-experimental-features 'nix-command flakes' \
       flake check /etc/nixos --no-build
   nix --extra-experimental-features 'nix-command flakes' \
       eval /etc/nixos#nixosConfigurations.<host>.config.sops.secrets \
       --apply 'x: builtins.attrNames x'
   ```

## Re-keying / adding zephyr as a recipient

`/etc/nixos/.sops.yaml` already names the local pubkey, so newly encrypted
secrets automatically include `zephyr`. For historical files:

```bash
cd /etc/nixos
PUBKEY=$(awk '/^# public key:/ {print $4}' ~/.age/key.txt)
# NOTE (sops 3.13.1): The single-file re-key example below is
# **not currently executable** as-written. `sops updatekeys --help`
# confirms this subcommand accepts ONLY:
#   --yes | --input-type | --enable-local-keyservice | --keyservice
# There is NO `--add` / `--add-recipient` / `--rm` flag in sops 3.13.1
# for adding age recipients via updatekeys. See "Recovery from key
# loss -> Rotation" below for the actual recovery path, and the
# "sops 3.13.1 updatekeys syntax (verified Aug 2026)" appendix for
# the full help evidence.
#
# Pseudocode once a future sops release adds the flag:
#   sops --config /etc/nixos/.sops.yaml updatekeys --add age \
#     "$PUBKEY" secrets/<feature>/<name>.yaml
```

 Verify the local `sops` binary's syntax — different sops revisions have
varied the flag names:

```bash
sops updatekeys --help 2>&1 | grep -E 'add|rm|yes' | head -20
```

*Verified Aug 2026 (sops 3.13.1)*: `sops updatekeys` accepts only
`--yes`, `--input-type`, `--enable-local-keyservice`, `--keyservice`.
There is **no `--add` / `--rm` flag for adding age recipients** in
this subcommand. The `rekey all files via updatekeys --add` example
in this doc is therefore not currently executable on sops 3.13.1;
see the `Recovery from key loss -> Rotation` section.

```bash
sops updatekeys --help 2>&1 | grep -E 'add|rm'
```

Batch against every encrypted file (uses `find` so it works in plain
`bash` without `shopt -s globstar`):

```bash
PUBKEY=$(awk '/^# public key:/ {print $4}' ~/.age/key.txt)
# NOTE (sops 3.13.1): The batch re-key loop below is also NOT
# currently executable. `updatekeys` has no `--add` flag in this
# version. The real recovery path is documented in
# "Recovery from key loss -> Rotation" — collect plaintext from
# secret owners and re-encrypt with `sops ... --encrypt --in-place`
# (uses `.sops.yaml` `creation_rules` to enroll zephyr's pubkey).
#
# Pseudocode (kept for reference; `--add`/`--rm` has been
absent from `sops updatekeys` for the duration of sops 3.x):
#   while read -r f; do
#     sops --config /etc/nixos/.sops.yaml updatekeys --yes \
#        --add age "$PUBKEY" "$f"
#   done < <(find /etc/nixos/secrets \
#              -type f \
#              \( -name "*.age" -o -name "*.yaml" -o -name "*.env.yaml" \))
```

Note: `--yes` is non-interactive AND accepts-prompting. Test on ONE file
first; the `--add age` form appends the local pubkey but does NOT
invalidate other recipients (use `--rm age <other-pubkey>` separately
if you want to retire a key).

## Recovery from key loss

- **One host can't decrypt; others can.** Generate a fresh key on the
  affected host, distribute its pubkey, run `sops updatekeys --add age
  <new-pubkey>` across the secret tree, then place the new private key
  wherever the registry expects. `age-keygen` from nixpkgs:

  ```bash
  nix --extra-experimental-features 'nix-command flakes' \
      run 'nixpkgs#age' -- age-keygen -o /tmp/new-age.key

  # Then sync to the canonical location used by sops-nix:
  sudo cp /tmp/new-age.key /etc/nixos/.age/key.txt
  sudo chown root:root /etc/nixos/.age/key.txt
  sudo chmod 600 /etc/nixos/.age/key.txt
  ```

  Note the `--` separator: `nix run 'nixpkgs#X' -- args...` is the
  correct form; the older `nix run 'nixpkgs#X' -c args...` is rejected
  by modern nix.

- **> **WARNING (high): rotation REPLACES the recipient set, not
> extends it.** Applying
> `sops --config /etc/nixos/.sops.yaml --encrypt --in-place`
> re-encrypts under `.sops.yaml` `creation_rules`, which lists ONLY
> zephyr's pubkey. The resulting file has ONLY zephyr as a recipient
> — every other host that could decrypt the previous envelope (up to 76
> historical recipients) loses decryption access on rotation.
> **Coordinate with all peer hosts (forge, nexus, sentry, krash3, and
> any external operator) before running rotation en masse**, or peer
> hosts will silently stop decrypting on their next `nixos-rebuild`.
> See also the WARNING block at the top of the `sops 3.13.1 updatekeys
> syntax` appendix.

Cluster-wide loss.** The orphan files (0/135 decrypt today) encode
  76 unique recipient X25519 tags (from prior audit). If the matching
  private keys are gone, those secrets are unrecoverable. Rotate
  everything: re-collect each secret from its owner/operator, store as
  plaintext under `/etc/nixos/secrets/<feature>/<name>.yaml`, and
  re-encrypt via `sops --config /etc/nixos/.sops.yaml
--encrypt --in-place`. The resulting file has ONLY zephyr as a
recipient (per `.sops.yaml` `creation_rules`) — coordinate with
all peer hosts before running, see WARNING in the
`sops 3.13.1 updatekeys syntax` appendix.

- **zephyr-specific.** Since 2026-07-08 zephyr sets
  `services.sops-secrets-registry.enable = true`, the registry `mkIf`
  block IS included and `nixos-rebuild switch` now **does** attempt to
  decrypt 89 secrets at activation. The Hermes bootstrap set and the
  re-keyed `ai/telegram-bot-token` decrypt successfully with zephyr's
  age key. The remaining "0/135 legacy decrypt mismatch" applies only to
  the historical files that were NOT re-encrypted under the zephyr-only
  `.sops.yaml` policy (e.g. the `monitoring/*` group, disabled on zephyr,
  and any unreferenced/orphan files) — those remain un-decryptable and
  out of scope until explicitly re-keyed.

## Operator manual

| Action                                            | Command |
|---------------------------------------------------|---------|
| Decrypt one file                                  | `SOPS_AGE_KEY_FILE=~/.age/key.txt sops --config /etc/nixos/.sops.yaml -d /etc/nixos/secrets/<feature>/<file>.yaml` |
| Re-encrypt in place                               | `sops --config /etc/nixos/.sops.yaml --encrypt --in-place <file>` |
| Add a recipient                                   | `sops --config /etc/nixos/.sops.yaml updatekeys --yes --add age <pubkey> <file>` |
| Verify flake parses                               | `sudo nix --extra-experimental-features 'nix-command flakes' flake check /etc/nixos --no-build` |
| Verify the host's `sops.secrets` attr-names       | `nix --extra-experimental-features 'nix-command flakes' eval /etc/nixos#nixosConfigurations.<host>.config.sops.secrets --apply 'x: builtins.attrNames x'` |
| Verify the host's `sops.age.keyFile`              | `nix --extra-experimental-features 'nix-command flakes' eval /etc/nixos#nixosConfigurations.<host>.config.sops.age.keyFile`  (returns `null` if the registry's `mkIf` block is gated off on that host) |
| Diff host vs canonical key                        | `sudo diff -q ~/.age/key.txt /etc/nixos/.age/key.txt` |
| List `.age` recipient tags (header parse)         | `head -c 600 <file>.age \| grep -oE '\-> X25519 [A-Za-z0-9+/=]+' \| sort -u` |

## Known issues / gotchas

- Of the legacy secret tree, the **other** subdir `.yaml` / top-level
  `.age` files that zephyr does NOT enable (and which were not re-keyed
  to zephyr's pubkey during the 2026-07-08 migration) still fail local
  decryption — this is the historical 0/135 mismatch, scoped to the
  unreferenced/legacy set. The secrets zephyr enables (89 entries) now
  decrypt successfully via sops-nix at activation.
- `/etc/nixos/` git tree is dirty (uncommitted); `nix` prints a warning
  but `flake check` itself succeeds (rc=0).
- `/etc/nixos/kubernetes/modules/ai-inference.nix` mentions
  `secrets/ai-gateway-zai-api-key.age` in **comments only** — those
  references are narrative, not live.
- `format = "binary"` means each `.yaml` secret stores its sops data as
  a JSON-encoded blob (`{"data":"ENC[...]"}`), not as YAML keys. Mixing
  plaintext into YAML-mode storage produces parse errors during
  activation — use `sops --input-type yaml` deliberately when
  re-encrypting YAML files from scratch.
- `nix run 'nixpkgs#X' -c args...` is the **old** syntax. Modern nix
  uses `nix run 'nixpkgs#X' -- args...` (note the `--` separator).
- `sops updatekeys` flag names differ across minor versions — always
  check `sops updatekeys --help` first.



## sops 3.13.1 updatekeys syntax (verified Aug 2026)

Verified via `sops updatekeys --help` against the local 3.13.1 install
on zephyr (2026-08-XX). The `updatekeys` subcommand accepts ONLY:

```
--yes / -y
--input-type
--enable-local-keyservice
--keyservice
```

There is **no `--add` or `--add-recipient` flag** for adding age
recipients. Flaky syntax like `--add age <X25519>` or
`-i <X25519>` are all rejected with `fatal: flag provided but not
defined`.

> **WARNING — rotation vs addition.** The "Rotation" recovery path
> documented elsewhere in this doc uses
> `sops --config /etc/nixos/.sops.yaml --encrypt --in-place`. This
> applies the **`.sops.yaml` `creation_rules`**, which lists ONLY the
> cluster_age (= zephyr's pubkey). The resulting file has ONLY zephyr
> as a recipient — every previously-encrypted file was created with
> up to 76 distinct historical recipients, and they will all lose
> decryption access on rotation. **Coordinate with all peer hosts**
> (forge, nexus, sentry, krash3, and any external operator) **before
> running rotation en masse**, or peer hosts will silently stop
> decrypting on their next `nixos-rebuild`. The semantics here are
> fundamentally different from `--add`, which (in older sops
> versions) was additive; `--encrypt --in-place` is a **replacement
> of the recipient set**, not an addition.

### Implication for the documented recovery path

The `## Re-keying / adding zephyr as a recipient` example in this doc
was authored against an older sops version where `updatekeys --add`
existed. On sops 3.13.1, that exact invocation is rejected.

To actually re-key the 135 legacy files, the supported paths on this
sops version are:

1.  **Rotation (re-encrypt-from-plaintext)** — see
    `## Recovery from key loss`. Plaintext gathered from secret
    owners is stored under `/etc/nixos/secrets/<feature>/<name>.yaml`,
    then re-encrypted via `sops --config /etc/nixos/.sops.yaml
    --encrypt --in-place` (uses `.sops.yaml` creation_rules and
    produces a file with ONLY the canonical pubkey as a recipient).

2.  **Manually edit encrypted files** — extract the sops data-ciphertext
    block from each file, build a new envelope with the desired
    recipients, re-encrypt and write back. This is brittle and
    out of scope.

3.  **Downgrade sops locally** to a version where `updatekeys --add`
    works (e.g. an older 1.x / 2.x). Out of scope because then
    `/etc/nixos/.sops.yaml` `creation_rules` semantics would also
    differ.

Path (1) is the supported recovery; paths (2)/(3) are escape hatches.

### Decryption state today

Plain `sops -d <file>` with `~/.age/key.txt` still fails for the
**legacy** secret files that were NOT re-encrypted under the zephyr-only
`.sops.yaml` policy — zephyr's pubkey is not embedded as a recipient in
any of those envelopes. This is the historical 0/135 mismatch, still
true for any file outside the set zephyr actually enables. The secret
files zephyr needs (Hermes bootstrap creds + the re-keyed
`ai/telegram-bot-token`, plus the other active feature-flag groups)
**were** re-keyed to zephyr's pubkey during the 2026-07-08 migration and
no longer hit this failure; sops-nix decrypts them at activation.



## Recommended next step (option b): smoke-test feature flag — DONE

The smoke-test described below was **executed as part of the 2026-07-08
migration**: `services.sops-secrets-registry.enable = true` now lives in
`hosts/zephyr/services.nix` (scoped to the 8 active feature flags,
`monitoring = false`), and `nixos-rebuild switch` decrypts the enabled
set at activation. The eval commands below now return the live state:

```bash
nix --extra-experimental-features 'nix-command flakes' \
    eval /etc/nixos#nixosConfigurations.zephyr.config.sops.secrets \
    --apply 'x: builtins.attrNames x'
# → 89 enabled secret names across aiServices/kubernetes/cloud/storage/
#   mining/automation/ci/selfHosting

nix --extra-experimental-features 'nix-command flakes' \
    eval /etc/nixos#nixosConfigurations.zephyr.config.sops.age.keyFile
# → "/etc/nixos/.age/key.txt"
```

**Decryption outcome:** the enabled set (including the Hermes bootstrap
credentials and the re-keyed `ai/telegram-bot-token`) decrypts
successfully with zephyr's age key — this is no longer a "fail at the
decrypt step" situation for the active secrets. The historical 0/135
mismatch is resolved *for the subset that zephyr actually enables*;
secret files outside that scope (and the disabled `monitoring/*` group)
remain latent and un-decryptable until explicitly re-encrypted under
`.sops.yaml`.

If you want a smoke-test that ALSO exercises decryption, the only
path is option (a) rotation via the recovery procedure documented in
`## Recovery from key loss` once the fleet is coordinated.

## Cross-references

- `/etc/nixos/STATUS.md` — cluster health / real-time state (footer
  contains a pointer to this doc)
- `/etc/nixos/AGENTS.md` — operational rules for AI agents working here
  (footer contains a pointer to this doc)
- `/home/j_kro/Projects/hermes-skills/provision-nixos-server/SKILL.md` —
  provisioning templates that reference `sops-nix`
- `/home/j_kro/Projects/hermes-skills/agenix-secrets/` — older agenix
  pattern (separate, complementary skill)
