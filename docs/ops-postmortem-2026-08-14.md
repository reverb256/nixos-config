# Ops Postmortem 2026-08-14 — Backup Wedge, Deploy Chain, SSH CA, Dendritic Quirk

Dense record of the 2026-08-14 incident chain. Every entry: symptom → root cause →
fix → verification. Use this to avoid repeating the mistakes. **Late-breaking:
the nexus/forge k3s "activating forever" + deploy error-code-4s were NOT an etcd
problem — the root cause was a duplicate `[nvidia]` containerd runtime table
(see the last section).**

---

## 1. Zephyr backup wedge — 173G tarball filled the root volume (CRITICAL)

**Symptom:** zephyr `/` (931G nvme0n1p2) at 100% (678M free and dropping).
`backup-to-garage.service` stuck `activating (start)` for 2h49m, 6.9G RAM peak,
164G written to disk. `systemctl disable` failed with "Read-only file system".

**Root cause:** the backup script tar'd EVERY source into
`/tmp/garage-backup-*/<src>.tar.gz`, then re-tar'd into a second archive
(`/tmp/cluster-backup-<date>.tar.gz`) before uploading — doubling disk. With
`PrivateTmp = true`, private /tmp is ON the root volume. One 173G source filled
the disk.

**Fix (committed `dc754349`, p1's `/data` exclusion `9f1512b8`):**
- Stream each source: `tar -czf - | aws s3 cp - "s3://$BUCKET/$PREFIX/$DATE/$src.tar.gz"`
- Dropped `PrivateTmp` + `ReadWritePaths = ["/tmp"]`
- Layout `s3://backups/cluster-backup/<YYYYMMDD-HHMMSS>/<src>.tar.gz`; rotation
  parses the dir date
- p1 excluded `/data` from zephyr backupPaths

**Verification:** `systemctl start backup-to-garage` → `[INFO] Streaming ...` in
journal; `df -h /` FLAT (166G free) while streaming the 487G /home/j_kro/Projects.

**Pitfalls for the script:** Nix `''...''` interpolation eats `${s3_key}` — use
`''${s3_key}`; region must be `garage` (`AWS_DEFAULT_REGION`) or
`AuthorizationHeaderMalformed us-east-1`; keys at
`/run/secrets/garage-s3-access-key-id` + `garage-s3-secret-key`; rotation parser
must match the NEW dir layout.

Full runbook: skill `backup-to-garage-streaming`.

---

## 2. Site-agency CI→Deploy chain — 9 distinct failures (all fixed)

The deploy ran on the sentry self-hosted runner (user `runner-siteagency`).
Failure → root cause → fix:

| # | Failure | Root cause | Fix |
|---|---|---|---|
| 1 | venv update failed | sentry disk 100% full | GC (freed 158G) |
| 2 | CI queued forever | no runner on sentry (dead file) | `ciRunners` + import services.nix |
| 3 | runner setup 401 | stale PAT secret | re-emitted via secretspec |
| 4 | SSH denied | no deploy key wired | CA-signed cert + TrustedUserCAKeys |
| 5 | key file missing | GH Actions `~`/HOME env unreliability | hardcoded `/var/lib/runner-siteagency/.ssh/` paths |
| 6 | `connection unexpectedly closed` | `/etc/hosts` loopback `127.0.0.2 sentry` (sentry.io block) — ssh hit wrong target | use IP `10.1.1.140` |
| 7 | `unix_listener bind` | runner ssh ControlMaster socket dir missing | `-o ControlMaster=no -o ControlPath=none` |
| 8 | venv source failed | sentry default shell is **fish** (can't source bash activate) | `bash -c '...'` |
| 9 | verify nested quoting | ssh→bash→python quote war | `scripts/verify_deploy.sh` (repo file) |

**Deploy is GREEN:** CI (42/42 tests) → rsync → venv → verify, all passing on
sentry.

---

## 3. SSH CA — cert auth works, authorized_keys stays empty

- Cluster CA pub committed at `certs/cluster-ssh-ca.pub`; private key sops at
  `secrets/infra/cluster-ssh-ca-key.yaml`.
- CA trust consolidated in `modules/system/ssh-ca.nix` TrustedUserCAKeys
  (cluster-CA@zephyr + YubiKey ECDSA + cluster CA). Do NOT add a duplicate
  TrustedUserCAKeys in ssh.nix (OpenSSH merges lines but it's two sources of
  truth).
- `AuthorizedKeysFile %h/.ssh/authorized_keys /etc/ssh/authorized_keys.d/%u` —
  NixOS-managed; hand-editing `~/.ssh/authorized_keys` is moot.

**Two sign/deploy pitfalls:**
1. `ssh-keygen -V +1h:+90d` produced a cert sshd rejected as "not yet valid"
   (clocks matched!). Always sign with EXPLICIT past-start timestamps:
   `-V 2026-08-13T21:00:2026-11-12`.
2. Passing key + cert as two `-i` flags → "Too many authentication failures"
   (MaxAuthTries=6). Use one IdentityFile (ssh auto-finds `<key>-cert.pub`) +
   `IdentitiesOnly yes` via a config file.

---

## 4. Dendritic eval quirk — mkOptionDefault firewall list silently collapses

**Symptom:** sentry's `networking.firewall.allowedTCPPorts = lib.mkOptionDefault
[22 10250 3100 3900 3901 9100 9900]` evaluated to `[22]`; deployed nftables
showed `tcp dport { 22, 30000-32767 }`; A2A peers got Errno 110.

**Root cause:** silent priority conflict in the composed dendritic module list
(a plain `=` at priority 100 beats ALL mkOptionDefaults). Merge works in
isolation but not in the composed graph.

**Fix:** `lib.mkForce` (priority 50) on the host file list. Eval then returns
`[ 22 3100 3900 3901 9100 9900 10250 ]` and the deployed nft accepts 9900.

**ALWAYS verify:** `nix eval .#nixosConfigurations.<host>.config.networking.firewall.allowedTCPPorts`
before deploying; `sudo nft list chain inet nixos-fw input-allow` after.

---

## 5. gitlawb flake input — path: breaks remote fetch

`gitlawb = { url = "path:./pkgs/gitlawb"; }` (same-repo subdir, shares .git)
evaluated locally but broke EVERY remote flake fetch (`deploy-nexus` pulls
origin/main): `error: cannot fetch input 'path:./pkgs/gitlawb?...' because it
uses a relative path`. Blocked all host evals/deploys.

**Fix:** `url = "git+https://github.com/reverb256/nixos-config?dir=pkgs/gitlawb";`
then `nix flake update gitlawb`. Works locally + remotely.

---

## 6. Sentry hermes 0.16.0 → 0.20.0 (A2A gateway)

- Sentry's own store couldn't resolve the 0.20.0 closure (base-toolchain
  cascade: coreutils/findutils/gawk/gnumake/bootstrap-stage-xgcc-stdenv failed).
- **Do NOT retry on-target.** Build on nexus, `nix copy --from ssh-ng://j_kro@nexus
  <store-path>`, `nix profile remove hermes-agent && nix profile install
  <store-path> --priority 5` (old entry wins by default otherwise).
- Gateway now serves `hermes-sentry` at 10.1.1.140:9900 (firewall via mkForce,
  see §4).
- Model: Bonsai-27B-Q1_0 via llama-server :8003. 503 "Loading model" is the load
  window — wait for `/health` → ok. Mid-generation crash/empty reply = turbo4 +
  256K KV overflow on AMD/Vulkan — reduce `-c` or drop turbo4; durable fix is
  the graph_mtp patch.

---

## Quick reference — commands that prove things

```bash
# firewall list before/after a change
nix eval .#nixosConfigurations.<host>.config.networking.firewall.allowedTCPPorts
sudo nft list chain inet nixos-fw input-allow

# cert-only auth test (one identity, IdentitiesOnly, explicit -F config)
ssh -F /tmp/deploy-ssh-config -o IdentitiesOnly=yes j_kro@10.1.1.140 'echo OK'

# A2A gateway health
curl http://10.1.1.140:9900/.well-known/agent-card.json
ss -ltnp | grep :9900

# backup streaming (watch journal; df stays flat)
systemctl start backup-to-garage
journalctl -u backup-to-garage -f
```

---

## 5. Nexus/Forge k3s "activating forever" — root cause: duplicate `[nvidia]` containerd runtime

**Symptom:** k3s stuck `activating (start)`, API :6443 → `503 "apiserver not ready"`,
`kubectl` → "unable to handle the request", and EVERY colmena deploy aborts
`error code: 4`. Looked like etcd/quorum for hours.

**Root cause:** `containerdConfigTemplate` in `modules/services/k3s-cluster.nix`
added an UNQUOTED `[plugins."...".runtimes.nvidia]` table while the nixpkgs k3s
module already generates the quoted `"nvidia"` + `"nvidia-cdi"` runtimes when
`hardware.nvidia-container-toolkit.enable = true`. TOML treats them as the SAME
table → `containerd: failed to unmarshal TOML: toml: table nvidia already
exists` → containerd exits 1 → k3s never ready.

**Where the error lives:** `/var/lib/rancher/k3s/agent/containerd/containerd.log`
(file — NOT journald). k3s fd 1/2 → internal socketpair, so `journalctl -u k3s`
is empty even when k3s logs a lot.

**Fix:** removed the duplicate table from the template (`61a432f7`). containerd
boots clean (`successfully booted in 0.1s`), k3s reaches ready.

**Pitfalls burned into us (don't repeat):**
- Foreground `k3s server` tests with `pkill` reset the etcd replay clock each time — each test adds 10+ min and masquerades as a new failure.
- `--cluster-reset` interrupted by a reboot leaves a half-state (`reset-flag` present + new member name); re-run to completion, and the "remove the cluster-reset flag" fatal on the second run is EXPECTED.
- The error-code-4 deploy abort is the skill-documented "k3s member stuck activating" case — check containerd.log FIRST, before any etcd surgery.
