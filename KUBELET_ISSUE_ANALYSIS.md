# Kubelet Binary Missing Issue - Analysis

## Date: 2026-03-14

## Issue Summary
The kubelet systemd service fails to start because the kubelet binary is missing from the kubernetes-1.35.0 package.

```
kubelet.service: Failed at step EXEC spawning /nix/store/...-kubernetes-1.35.0/bin/kubelet: No such file or directory
```

## Root Cause: Nixpkgs Packaging Regression

### Expected Behavior
The kubernetes-1.35.0 package should include these binaries:
- kube-apiserver ✓ (present)
- kube-controller-manager ✓ (present)
- kube-scheduler ✗ (missing)
- kube-proxy ✗ (missing)
- kubeadm ✗ (missing)
- **kubelet ✗ (missing - CRITICAL)**

### Investigation Findings

1. **Derivation Configuration**: The package derivation at `/nix/store/mwcrzj9jvaynxp7qdv6cijl2sid61bbk-source/pkgs/by-name/ku/kubernetes/package.nix` correctly includes kubelet:

```nix
components ? [
  "cmd/kubeadm"
  "cmd/kubelet"     # ← Included in build
  "cmd/kube-apiserver"
  "cmd/kube-controller-manager"
  "cmd/kube-proxy"
  "cmd/kube-scheduler"
],
```

2. **Build Log Evidence**: The build log shows kubelet WAS built and processed:

```
shrinking /nix/store/.../bin/kubelet
stripping (with command strip -S -p) in /nix/store/.../bin
```

3. **Derivation JSON Confirms**: The derivation shows:
```json
"WHAT":"cmd/kubeadm cmd/kubelet cmd/kube-apiserver cmd/kube-controller-manager cmd/kube-proxy cmd/kube-scheduler"
```

4. **Install Phase Script**: Should install all components:
```bash
for p in $WHAT; do
  install -D _output/local/go-bin/${p##*/} -t $out/bin
done
```

5. **Actual Package Contents**: Only 2 binaries present:
```
/nix/store/m40vni3q2bra3gi219akcfpm4kmvafb1-kubernetes-1.35.0/bin/kube-apiserver
/nix/store/m40vni3q2bra3gi219akcfpm4kmvafb1-kubernetes-1.35.0/bin/kube-controller-manager
```

### Conclusion
This is a **nixpkgs packaging regression** where the build process creates all binaries but only 2 of 6 end up in the final package. The most likely causes:
1. Silent failure in the install phase loop
2. Post-build cleanup removing binaries
3. Race condition during multi-binary install

## Impact

### Kubernetes Cluster: **COMPLETELY NON-FUNCTIONAL**
- All 4 nodes cannot join the cluster (kubelet required)
- No pod scheduling possible
- No container runtime integration
- Control plane components (apiserver, controller-manager, scheduler) run but have no nodes to manage

## Solution Options

### Option 1: Update Nixpkgs (Recommended)
Update to a newer nixpkgs revision where this issue is fixed:
```bash
nix flake lock --update-input nixpkgs
sudo nixos-rebuild switch --flake .
```

### Option 2: Use Older Kubernetes Version
Pin kubernetes to 1.34.x or earlier in the configuration (may not be available in current nixpkgs).

### Option 3: Manual Kubelet Installation
Install kubelet from official Kubernetes binaries (not recommended - breaks NixOS purity).

## Next Steps
1. Update nixpkgs input to latest
2. Test rebuild of kubernetes package
3. Verify kubelet binary is present
4. Rebuild system and test Kubernetes cluster

## References
- Package definition: `/nix/store/mwcrzj9jvaynxp7qdv6cijl2sid61bbk-source/pkgs/by-name/ku/kubernetes/package.nix`
- Installed package: `/nix/store/m40vni3q2bra3gi219akcfpm4kmvafb1-kubernetes-1.35.0`
- Kubelet service: `/nix/store/hs1qh4w1cqrs7hdkj9yxihvrflwkgfx8-unit-kubelet.service/kubelet.service`
