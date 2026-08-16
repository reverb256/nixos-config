# Known issues, hardening, and deployment lessons

**Last Verified:** 2026-08-16
**Status:** Reference
**Owner:** j_kro

## Security hardening (implemented)

- **NodePort restriction** — nftables `extraInputRules` in
  `modules/services/k3s-cluster.nix` drops NodePort (30000–32767) traffic except
  from `10.1.1.0/24` + localhost.
- **etcd encryption at rest** — `k3s-secrets-encryption` oneshot generates
  `EncryptionConfiguration` from a sops-distributed AES key
  (`secrets/infra/k3s-encryption-key.json`).
- **K8s audit policy** — `k3s-audit-policy` oneshot installs `auditPolicyFile`;
  metadata for all requests, bodies for secrets/RBAC/admission changes.
- **Falco runtime security** — DaemonSet in `monitoring` namespace.
- **Pod Security Standards** — `enforce=baseline/audit=restricted` on workload
  namespaces; system namespaces `privileged`.
- **`:latest` tags** — blocked by admission policy; images pinned.

## Silent-deletion incident (2026-07-20 → 2026-07-30)

Commit `4732cfe3` ("fix(spotx): update spotx.sh hash") accidentally deleted 265
lines from `modules/services/k3s-cluster.nix`, regressing audit policy, etcd
encryption, and NodePort restrictions. Recovered 2026-07-30. Lesson: scope
commits to their stated purpose; a misnamed commit hid a serious regression.

## Deployment protocol (Sentry lesson)

Never use `nixos-anywhere` for hosts with existing data — it is a provisioning
tool for fresh bare metal.

```bash
# 1. Build the closure on Nexus
sudo nix build "path:/etc/nixos#nixosConfigurations.<host>.config.system.build.toplevel" --no-link --print-out-paths
# 2. Copy the closure
nix copy --to "ssh://j_kro@<ip>" /nix/store/<hash>-nixos-system-<host>-...
# 3. Activate with a full switch
ssh j_kro@<ip> "sudo nix-env -p /nix/var/nix/profiles/system --set /nix/store/<hash>... && sudo /nix/store/<hash>.../bin/switch-to-configuration switch"
```

Post-deploy: check generation count, `systemctl list-units --state=failed`,
recovery specialisation in the boot menu, and `/run/secrets/` decryption.

The supported entry point is `just deploy [<host>]`. Use
`scripts/deploy/deploy-host.sh <hostname>` only for its rescue/direct-host
behavior. See `DEPLOYMENT-LESSONS.md` for the full postmortem.

## Secret-leak audit (2026-08-16)

A pre-public-flip audit found live credentials in the tree and history. Two
plaintext SOPS age private keys were committed in
`hosts/forge/configuration.nix` (recipient for the whole sops store), plus
plaintext env dumps (`env-vars`, `.secretspec.env`,
`secrets/casdoor/mcp-gateway-credentials.env`) and a `secrets.pre-recovery-*`
backup tree. The config leak is removed; the remaining exposure lives in git
history, so **rotation is mandatory before the repo goes public** — see
`docs/runbooks/credential-rotation.md`.

The forge age key now lives at `/persistent/etc/sops/age/key.txt` (bind-mounted
by `hosts/forge/preservation.nix`), seeded once by the operator and never
written into the nix config.
