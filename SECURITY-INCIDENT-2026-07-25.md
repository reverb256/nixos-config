# Security Incident: SOPS Secret Data Loss & Git Recovery (2026-07-25)

## TL;DR — Recovery Was Successful

**17 of 18 `secretspec`-routed secrets were recovered intact from git history (commit `627a19e3`) via `git checkout`.** The placeholder overwrite was confined to the working tree and was never committed. Only `SAMSUNG_TV_TOKEN` (which had a stale route comment pointing at a file that never existed under that name in git) requires operator-side rotation.

Verify the recovery commit yourself:

```bash
git -C /etc/nixos log --oneline 627a19e3 -1
# expected: 627a19e3 feat: add 66 sops-nix encrypted secrets + .sops.yaml
```

## What Happened

During a secretspec migration on `zephyr`, an agent-driven session prematurely overwrote
the working tree's routed SOPS files with placeholder strings
(`PLACEHOLDER_REPLACE_AFTER_KEY_ROTATION`) before being interrupted. The overwrite was
**never committed**, so git history was untouched.

## Recovery Steps (in order)

1. **Key recovery**: Located the active cluster key at `/etc/nixos/.age/key.txt` —
   the canonical sops-nix key location per `modules/services/rclone-example.md`.
   The earlier "key lost" framing was wrong; the key was simply in a non-default path.
2. **Recipient harmonization**: Reverted `.sops.yaml` from an accidental session
   rotation. Final recipient set has **four** entries:
   - `cluster_age` (private key: `/etc/nixos/.age/key.txt`)
   - `zephyr_age_v2` (private key: `~/.config/sops/age/keys.txt`)
   - `yubikey_nano` (YubiKey 5 NFC — PIV slot, must be plugged in)
   - `yubikey_nfc` (YubiKey 5 NFC — alternate slot)
3. **Backup before any destructive action**:
   `sudo cp -a /etc/nixos/secrets /etc/nixos/secrets.pre-recovery-2026-07-25`
4. **Git-based data restoration**:
   `git -C /etc/nixos checkout 627a19e3 -- secrets/`
5. **Recipient re-alignment**:
   `sudo SOPS_AGE_KEY_FILE=/tmp/combined-keys.txt find /etc/nixos/secrets -name '*.yaml' -exec sops updatekeys -y {} \;`
6. **Validation**: 17/18 routed files decrypt to real values via the local fork's
   sops provider. The 18th file (`secrets/default/activepieces.yaml` for
   `SAMSUNG_TV_TOKEN`) decodes to the placeholder.

## Remaining Operator Action

### 🟢 Verification (must-do before declaring cluster healthy)

For these three catastrophic items, **confirm the values recovered from
`627a19e3` still match what your wallet / backup system expects today**.
Git restores the value as it was at that commit — if you've rotated these
externally since, the git copy is stale.

- [ ] `ETHEREUM_WALLET_KEY` — confirm wallet still holds expected funds
- [ ] `MONERO_WALLET_KEY` — same
- [ ] `BACKUP_ENCRYPTION_KEY` — confirm against a recent restic/rclone backup

### 🟠 SAMSUNG_TV_TOKEN — still placeholder

The routed file `secrets/default/activepieces.yaml` contains the placeholder.
The validator's `✓` for `SAMSUNG_TV_TOKEN` is misleading: it reflects the
secretspec resolver falling through to env/dotenv defaults, not a successful
sops decryption. **Action**: rotate the Samsung TV WebSocket auth token at
the TV's admin UI and replace the placeholder in
`/etc/nixos/secrets/default/activepieces.yaml`, then
`sops updatekeys -y` to align recipients.

(The original route comment pointed at "secrets/default/activepieces.yaml"
but that filename never matched a real git-tracked file — likely a long-standing
typo. Naming fix deferred; the placeholder file lives at the typo'd path for now.)

### 🟡 YubiKey resilience on zephyr

`pcscd` runs on zephyr but its hotplug layer cannot find the CCID driver bundle
at the hardcoded `/var/lib/pcsc/drivers` path. The fix is one symlink:

```bash
sudo ln -sf /nix/store/jw2pnlc6syr24biaxmhm7kn6kfp2xm4j-ccid-1.7.1/pcsc/drivers/ifd-ccid.bundle \
            /var/lib/pcsc/drivers/ifd-ccid.bundle
sudo systemctl restart pcscd   # or restart manually if not a systemd unit
```

Until that fix is applied, the two YubiKey recipients in `.sops.yaml` are
**registered but unused** on zephyr — decryption falls through to `cluster_age`
or `zephyr_age_v2` automatically (SOPS OR-semantics). Non-blocking for
Phase 1; blocking if zephyr loses both software keys.

## Security Insight (must-not-miss)

**Of the four recipients, only the two YubiKey entries require physical token
presence.** `cluster_age` and `zephyr_age_v2` are both plaintext files on
zephyr (`/etc/nixos/.age/key.txt` and `~/.config/sops/age/keys.txt`
respectively). A host-level compromise yields both — the four-of-four
recipient count does NOT mean four-of-four independent attack vectors. The
YubiKey entries are the only ones that survive a host compromise.

## Lessons Learned (the actual insight, not the obvious ones)

1. **Never run `sops updatekeys -y` on a working tree without first running
   `sops -d` on a representative file to confirm decryption works.** The
   interrupted session ran the mass sweep first and never saw the placeholder
   overwrite until too late. **Spot-check first, sweep second.**
2. **Git is the ultimate source of truth for committed secrets.** Even when
   the working tree is destroyed, `git checkout <commit> -- <path>` recovers
   the encrypted originals — provided the recipients in `.sops.yaml` at that
   commit match keys you still possess.
3. **Never declare "key lost" without first checking canonical paths.** The
   original `cluster_age` key was at `/etc/nixos/.age/key.txt` the whole
   time — the sops-nix canonical location. Earlier agents searched
   `~/.config/sops/age/keys.txt` (the SOPS default) and missed it.
4. **Pause on user interrupt.** When the user said the workflow was wrong,
   the correct response is to STOP and present findings, not to drive
   forward with the in-progress plan.

## Verification Commands (run after each operator rotation)

```bash
# Confirm validator passes for production
SECRETSPEC_SOPS_PROVIDER_BIN=/nix/store/dsxibjhk0g7fqwvsjlxdhm8n398z7qk0-secretspec-provider-sops-0.1.0/bin/secretspec-provider-sops-protocol \
SOPS_AGE_KEY_FILE=/tmp/combined-keys.txt \
/home/j_kro/Projects/secretspec-core/target/release/secretspec \
  check --profile production

# Confirm keys file is current on every host that needs to decrypt
sudo rsync /etc/nixos/.age/key.txt otherhost:/etc/nixos/.age/key.txt
```

Success criteria: validator reports 0 missing required routes that should
have sops backing (currently only `SAMSUNG_TV_TOKEN` until operator rotates).

## Open Workstreams (not in scope of this incident)

- Nexus & sentry hardware-config drift (separate incident — see commit `0a5c113b7`)
- pcscd hotplug/CCID driver path on zephyr (recipe above; non-blocking)
- Cleanup `.sops.yaml.bak-2026-07-25` once git history is confirmed clean