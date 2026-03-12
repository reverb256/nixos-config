# Distributed Builds - Immutable Configuration

## CRITICAL: DO NOT MODIFY THESE FILES WITHOUT THOROUGH TESTING

The distributed builds configuration consists of TWO separate files that MUST stay in sync:

### 1. `/etc/nixos/machines.nix` (Machines FILE Format)
**Purpose**: Used by Colmena for distributed builds during deployment
**Format**: Simple text file (NOT Nix expressions!)
**Structure**:
```
# Format: protocol://user@host system ssh-key max-jobs speed-factor supported-features mandatory-features
ssh-ng://j_kro@zephyr x86_64-linux - 8 8 kvm,big-parallel -
ssh-ng://j_kro@nexus x86_64-linux - 6 5 big-parallel -
ssh-ng://j_kro@forge x86_64-linux - 2 2 kvm -
ssh-ng://j_kro@sentry x86_64-linux - 4 4 big-parallel -
```

**Fields**:
- protocol://user@host: SSH connection string
- system: Target platform (x86_64-linux)
- ssh-key: Path to SSH key (- = use default)
- max-jobs: Concurrent build jobs (K8s-aware: conservative)
- speed-factor: Relative speed (higher = faster)
- supported-features: Comma-separated features (kvm, big-parallel)
- mandatory-features: Required features (- = none)

### 2. `/etc/nixos/modules/system/distributed-builds.nix` (Nix Attribute Format)
**Purpose**: Configures each node's buildMachines setting
**Format**: Nix attribute set
**Structure**: `nix.buildMachines = [ ... ]`

**CRITICAL**: Both files MUST have identical:
- Hostnames
- maxJobs values
- speedFactor values
- supportedFeatures
- Usernames (j_kro)

## IDEMPOTENCY REQUIREMENTS

1. **Self-Exclusion**: Each node must NOT list itself as a builder
   - Prevents SSH-to-self loopback
   - Avoids nix-daemon lock contention
   - Implemented via: `lib.filter (m: m.hostName != currentHost)`

2. **SSH Key Configuration**: 
   - All nodes must have SSH key access to each other
   - User: j_kro (NOT root)
   - Protocol: ssh-ng (efficient binary protocol)

3. **K8s-Aware Resource Limits**:
   - zephyr: 8 jobs (control plane stability)
   - nexus: 6 jobs (NFS/PVC I/O headroom)
   - forge: 2 jobs (GPU workload priority)
   - sentry: 4 jobs (monitoring stack needs CPU)

## VERIFICATION CHECKLIST

After ANY change, verify:
```bash
# 1. Check machines file format
cat /etc/nixos/machines.nix

# 2. Test colmena evaluation
nix run github:zhaofengli/colmena -- eval

# 3. Test local build
nixos-rebuild build --flake .#zephyr

# 4. Verify distributed builds work
nix-build -E 'with import <nixpkgs> {}; hello'

# 5. Check all nodes have correct /etc/nix/machines
ssh zephyr "cat /etc/nix/machines"
ssh nexus "cat /etc/nix/machines"
ssh forge "cat /etc/nix/machines"
ssh sentry "cat /etc/nix/machines"
```

## CHANGE PROCESS

1. Make changes to BOTH files
2. Update documentation
3. Test with `nixos-rebuild build`
4. Deploy to ONE node first
5. Verify distributed builds work
6. Deploy to remaining nodes
7. Update this document with change rationale

## ROLLBACK PLAN

If distributed builds break:
1. Revert both files to last working version
2. Run `nixos-rebuild switch` on all nodes
3. Verify /etc/nix/machines is correct on all nodes
4. Test with a simple build: `nix-build -E 'with import <nixpkgs> {}; hello'`

## REFERENCES

- Nix Manual: https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html
- Colmena: https://hyperfine.cachix.org/colmena/
- Module: modules/system/distributed-builds.nix
- Machines File: machines.nix
