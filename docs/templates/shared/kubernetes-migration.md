## Kubernetes Migration

### Overview
Migrating from systemd services to Kubernetes using `services.kubernetes` (full upstream, not K3s). See `/etc/nixos/ROADMAP.md` for the complete 9-week plan.

### Migration Phases
1. **Week 1-2**: Bootstrap single-node cluster on Zephyr
2. **Week 2-3**: Add worker nodes (Nexus, Forge, Sentry)
3. **Week 3-4**: Migrate stateful services (PostgreSQL, Redis)
4. **Week 4-6**: Migrate stateless services
5. **Week 6-7**: GPU workloads with device plugins
6. **Week 7-8**: Monitoring and observability
7. **Week 8-9**: Cleanup and optimization

### Architecture
**Control Plane (Zephyr)**: API server, etcd, Flannel CNI, CoreDNS
**Worker Nodes**: Nexus (storage), Forge (GPU), Sentry (monitoring)
**Storage**: Longhorn (distributed), NFS (shared), local (databases)
**Networking**: Tailscale VPN, Flannel VXLAN, Caddy ingress

### GPU Passthrough
```nix
# NVIDIA nodes
hardware.graphics.nvidia.enable = true;

# AMD nodes
hardware.graphics.amdgpu.enable = true;

# Mixed vendor (Forge) - deploy both plugins
```

### Key Commands
```bash
# Cluster management
kubectl get nodes
kubectl get pods --all-namespaces
kubectl logs <pod-name> -n <namespace>

# Deployment
kubectl apply -f manifests/
kubectl rollout restart deployment/<name> -n <namespace>

# Storage
kubectl get pv,pvc -n <namespace>
```

### Service Migration Workflow
1. Create Kubernetes manifest (Deployment + Service)
2. Test in development namespace
3. Migrate data (if stateful): `pg_dump` → `kubectl cp`
4. Switch traffic to Kubernetes service
5. Monitor and rollback if needed

### NixOS Configuration
```nix
services.kubernetes = {
  enable = true;
  roles = ["master" "node"];
  apiserverAddress = "https://10.0.0.10:6443";
  podNets = ["10.244.0.0/16"];
  easyCerts = true;
};

virtualisation.docker.enable = true;
```

### Documentation
- **Full Plan**: `/etc/nixos/ROADMAP.md`
- **Kubernetes Docs**: https://kubernetes.io/docs/
- **NixOS Module**: https://search.nixos.org/options?query=services.kubernetes
