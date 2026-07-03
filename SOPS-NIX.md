# SOPS-NIX — secrets management

> **TL;DR.** sops-nix is wired into `/etc/nixos/common-modules-list.nix`.
> The registry module `modules/system/sops-secrets-registry.nix` (569 lines)
> declares secrets behind per-host feature flags, gated by a master
> `services.sops-secrets-registry.enable` (default: `false`). On **all 5
> hosts today** that toggle is left at its default — including `zephyr` —
> so the registry's entire `mkIf` block is **inert**; `nixos-rebuild
> switch` does NOT attempt any decryption. The 0/135 decrypt mismatch
> (top-level `.age` + subdir `.yaml`) is **latent**, not active, and only
> matters the moment any host opts in via
> `services.sops-secrets-registry.enable = true`.

## Current state

- **Module wiring:** `common-modules-list.nix` line 8
  (`inputs.sops-nix.nixosModules.default`) + line 9 (`./modules/system/sops-secrets-registry.nix`).
- **Hosts:** `forge`, `nexus`, `sentry`, `zephyr`, `krash3` (defined at
  `flake.nix:260`; assembled via `mkNixosSystem` at `flake.nix:284`).
- **Per-host flags:** none of the 5 `hosts/<host>/configuration.nix`
  files set `services.sops-secrets-registry.enable = true` (or any
  `services.sops-secrets-registry.<feature> = true`). Therefore the
  registry's `config = mkIf ...` block is **not** included in any host's
  evaluation. Concretely:
  - `nix eval ...#nixosConfigurations.zephyr.config.sops.age.keyFile`
    returns `null` (the registry never sets it on this host).
  - `nix eval ...#nixosConfigurations.zephyr.config.sops.secrets
    --apply 'x: builtins.attrNames x'` returns `[]`.
- **Canonical recipient:** `/etc/nixos/.sops.yaml` (git-tracked,
  uncommitted) lists **one** recipient:
  `age1p98yp8w64rdugp03332gxnz5v2vcnucn69cs5qm6s2l2u7epqfcqmu2pqe` —
  identical to `/home/j_kro/.age/key.txt`. Newly-encrypted secrets will
  therefore decrypt on `zephyr` once any host enables the registry.
- **Pre-policy legacy (re-key BLOCKED on zephyr; see Operational decision below):** all 64 top-level `*.age` files + ~71 subdir
  `*.yaml`/`*.env.yaml` files are encrypted to historical recipient sets
  that do NOT include `zephyr`'s pubkey. They decrypt 0/135 with the
  local key. Treatment: re-key with `sops updatekeys --add age <pubkey>`
  if/when actually needed; otherwise leave untouched.

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

- **Cluster-wide loss.** The orphan files (0/135 decrypt today) encode
  76 unique recipient X25519 tags (from prior audit). If the matching
  private keys are gone, those secrets are unrecoverable. Rotate
  everything: re-collect each secret from its owner/operator, store as
  plaintext under `/etc/nixos/secrets/<feature>/<name>.yaml`, and
  re-encrypt via `sops --config /etc/nixos/.sops.yaml
--encrypt --in-place`. The resulting file has ONLY zephyr as a
recipient (per `.sops.yaml` `creation_rules`) — coordinate with
all peer hosts before running, see WARNING in the
`sops 3.13.1 updatekeys syntax` appendix.

- **zephyr-specific.** Because `config.sops.secrets = null/[]` here
  today, **no** current `nixos-rebuild switch` will attempt to decrypt
  ANY file. The "0/-135 mismatch" is latent — it only surfaces when a
  host opts in via `services.sops-secrets-registry.enable = true`.

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

- 0/71 subdir `.yaml` files decrypt locally today (pre-`.sops.yaml` policy).
- 0/64 top-level `.age` files decrypt locally today (legacy recipients).
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

Plain `sops -d <file>` with `~/.age/key.txt` continues to fail for all
135 legacy files because zephyr's pubkey is not embedded as a recipient
in any of them (chicken-and-egg, separate concern from syntax).



## Recommended next step (option b): smoke-test feature flag

The failure of option (a) (rekey all 135 secrets) does not invalidate
the configuration wiring on zephyr. The most useful next action is a
smoke-test that confirms the registry correctly picks up secrets when
enabled:

```nix
# hosts/zephyr/configuration.nix
services.sops-secrets-registry.enable    = true;
services.sops-secrets-registry.mining   = true;   # low-risk isolated feature
```

After application:

```bash
nix --extra-experimental-features 'nix-command flakes' \
    eval /etc/nixos#nixosConfigurations.zephyr.config.sops.secrets \
    --apply 'x: builtins.attrNames x'

nix --extra-experimental-features 'nix-command flakes' \
    eval /etc/nixos#nixosConfigurations.zephyr.config.sops.age.keyFile
```

**Expected outcome:**

- First eval returns `["xmrig-password" "xmrig-rpc-password" ...]`
  (or whatever mining entries the registry declares).
- Second eval returns `"/etc/nixos/.age/key.txt"`.

**What this DOES NOT test:** decryption itself. Even with the flag
enabled, `nixos-rebuild switch` will attempt to decrypt the files and
fail at the decrypt step (zephyr's pubkey is NOT a recipient of any
legacy mining YAML). The valuable signal from option (b) is that
*registry, file paths, and key-file resolution are correct up to the
decrypt step*, independently of the recipient-mismatch issue.

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
