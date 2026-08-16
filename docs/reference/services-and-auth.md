# Services, auth, and routing reference

**Last Verified:** 2026-08-16
**Status:** Reference
**Owner:** j_kro

Reference for SSO/OIDC, the service↔network bridge, Caddy routing, DNS, the
cluster-mesh SSH account, and the Nexus DE VM.

## Central SSO

Casdoor OIDC (`auth.lan`) → oauth2-proxy (`central-auth.service`, port 4180) →
Caddy `forward_auth`. Deployed on Zephyr + Nexus.

| Type | Services |
|------|----------|
| Public (no auth) | dashboard.lan, gitea.lan, vaultwarden.lan, n8n.lan |
| Proxy SSO (forward_auth) | haven.lan, grafana.lan, mission-control.lan, qdrant.lan, brain.lan, ai-inference.lan, workspace.lan |
| Native OIDC (Casdoor) | grafana.lan, ai-inference.lan (JWT/JWKS), gitea.lan, openwebui.lan |

n8n, Haven, Mission Control, Kagent, Qdrant, Vaultwarden, and Workspace have no
usable generic OIDC and use their own or proxy auth.

## Service ↔ network bridge

`kubernetes/service-ports.nix` is the **single source of truth** for NodePorts.
Both Zephyr Caddy (`hosts/zephyr/caddy-routes.nix`) and Nexus cluster Caddy
(`modules/services/cluster-services.nix`) import it. Flow:

```
service-ports.nix ──import──► caddy-routes.nix (zephyr)
                   ──import──► cluster-services.nix (nexus)
                   ──consume──► K8s Services (nodePort must match)
```

- All `.lan` domains → VIP `10.1.1.100` (Keepalived MASTER on zephyr); unbound on
  all nodes with `local-zone "lan." static`.
- Do **not** deploy oauth2-proxy as a K8s sidecar — use the NixOS `central-auth`
  service (sidecars removed 2026-05-02).
- Do **not** add a static route for the K8s service CIDR `10.43.0.0/16` via
  `flannel.1`; kube-proxy owns ClusterIP translation. Host access is via NodePort
  through Caddy.
- Grafana runs only as K8s (monitoring namespace, sentry, NodePort 32102). The
  NixOS Grafana module was deleted 2026-07-14.

## Cluster-mesh SSH account

`cluster-mesh@10.1.1.x` (system user, no shell) is the service-to-service SSH
identity. Key: `/var/lib/cluster-mesh/.ssh/id_ed25519` (sops-managed
`secrets/cns-ssh-key.age`). Used by `cns-watcher`, `nexus-exec-tunnel`,
`cns-health.timer`. Never use `root@10.1.1.x` in automated units.

## Nexus DE VM (libvirt/QEMU)

Windows 11 VM on nexus; source of truth `modules/services/nexus-de-vm.nix`.
The RTX 3060 Ti stays on the `nvidia` driver for inference; `nexus-de-vm.service`
runs a coordinator that drains GPU processes, rebinds to `vfio-pci`, starts the
VM, and reverses on stop. 8 vCPU, 24Gi RAM, UEFI+TPM, Spice on port 5900.

```bash
systemctl start|stop|status nexus-de-vm
virsh console nexus-de
```
