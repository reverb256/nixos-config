# GitOps Repository Structure for GPU Scheduler
# Implements OpenGitOps principles with ArgoCD/Flux compatibility

## Repository Structure

```
gitops-repo/
├── base/                           # Base manifests (environment-agnostic)
│   ├── yunikorn/                   # YuniKorn scheduler
│   │   ├── namespace.yaml
│   │   ├── helm-release.yaml
│   │   └── values.yaml
│   ├── volcano/                    # Volcano scheduler
│   │   ├── namespace.yaml
│   │   ├── helm-release.yaml
│   │   └── values.yaml
│   ├── security/                   # Security policies
│   │   ├── serviceaccounts.yaml
│   │   ├── rbac.yaml
│   │   ├── networkpolicies.yaml
│   │   └── pod-security-standards.yaml
│   ├── networking/                 # Network policies
│   │   └── default-deny.yaml
│   └── operational/                # Operational resources
│       ├── pdb.yaml
│       ├── resourcequota.yaml
│       └── servicemonitor.yaml
├── overlays/                       # Environment-specific overlays
│   ├── development/                # Development environment
│   │   ├── kustomization.yaml
│   │   ├── patches/
│   │   └── values/
│   ├── staging/                    # Staging environment
│   │   ├── kustomization.yaml
│   │   ├── patches/
│   │   └── values/
│   └── production/                 # Production environment
│       ├── kustomization.yaml
│       ├── patches/
│       └── values/
└── apps/                           # App-of-apps pattern
    └── gpu-scheduler-app-of-apps.yaml
```

## OpenGitOps Principles Compliance

### 1. Declarative ✅
- All infrastructure defined as YAML manifests
- No imperative kubectl commands in production
- Helm releases defined as HelmRelease resources

### 2. Versioned and Immutable ✅
- Git is single source of truth
- All changes tracked via git commits
- Rollback via git revert (not kubectl)

### 3. Pulled Automatically ✅
- ArgoCD/Flux continuously syncs cluster state
- No manual kubectl apply in production
- Automated drift detection and remediation

### 4. Continuously Reconciled ✅
- Controllers continuously reconcile actual vs desired state
- Auto-healing from manual changes
- Self-healing infrastructure

## Environment Strategy

| Environment | Purpose | Sync Policy | Auto-Prune |
|-------------|---------|-------------|------------|
| Development | Testing | Automatic | Yes |
| Staging | Pre-production | Automatic | Yes |
| Production | Production | Manual | Yes |

## Promotion Workflow

```
development → staging → production
     ↓            ↓           ↓
  Auto-sync   Auto-sync   Manual-sync
```

## Deployment Safety

### Pre-Sync Hooks
- Validation: `kubectl diff` shows changes
- Testing: Pre-sync tests in staging
- Approval: Manual approval for production

### Post-Sync Hooks
- Health checks: Verify pod readiness
- Smoke tests: Run basic functionality tests
- Rollback: Auto-rollback on failure

## Rollback Strategy

```bash
# Option 1: Git revert
git revert <commit>
git push

# Option 2: ArgoCD rollback
argocd app rollback gpu-scheduler

# Option 3:kubectl rollout undo
kubectl rollout undo deployment/ai-inference-gateway -n ai-inference
```
