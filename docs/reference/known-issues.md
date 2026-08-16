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

## Sops envelope-format regression (2026-08-16)

`format = "binary"` in `sops-install-secrets` requires a JSON sops envelope
(`json.Unmarshal` at `pkgs/sops-install-secrets/main.go:514`). The age-key
rotation (`5f188591b`, 2026-08-16) ran `sops updatekeys` on all 79 sops files,
rewriting JSON envelopes to YAML envelopes (`data: ENC[...]` + `sops:` block).
Every binary-format secret then failed at build AND runtime with
`cannot parse json of '.../file.yaml': invalid character 'd' looking for beginning of value`.

Fix (`389fc2697`): the registry now defaults to `defaultSopsFormat = "yaml"`
with `defaultSopsKey = "data"`. Secrets without an explicit `sopsFile` inherit
the registry default file — give each one its real file (the
`cloud/cloudflared-token` case was silently binding the nvidia key file).
Re-encrypting the files back to JSON is blocked by the YubiKey hardware
requirement, so YAML envelopes are the new normal.

## Freebuff Desktop launcher lessons (2026-08-16)

- PATH order matters: `~/.nix-profile/bin` precedes `/run/current-system/sw/bin`,
  so the home-manager wrapper always wins for `freebuff-desktop-latest`; the
  NixOS system launcher was a duplicate.
- NVIDIA Electron AppImages need more than `VK_ICD_FILENAMES`. The working
  `launchEnv` set: `__EGL_VENDOR_LIBRARY_FILENAMES` → the glvnd vendor JSON
  (`/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json`), libglvnd-first
  `LD_LIBRARY_PATH`, `LIBGL_DRIVERS_PATH`, `GDK_BACKEND=wayland`,
  `MOZ_ENABLE_WAYLAND=1`.
- Keep `.desktop` entries declarative: HM emits
  `~/.local/share/applications/freebuff-desktop.desktop` as a symlink; the
  original hand-placed file was the violation that started this.
- The AppImage runtime was broken anyway (`libz.so.1: wrong ELF class`); the
  icon (`usr/share/icons/hicolor/512x512/apps/@codebufffreebuff-desktop.png`)
  ships from the NixOS module instead (`modules/services/assets/freebuff-icon.png`).
