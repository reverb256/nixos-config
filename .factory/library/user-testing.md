# User Testing Surface

## Validation Surface

**Surface**: Kubernetes API and HTTP service endpoints
**Tools**: kubectl, curl, ssh
**No browser testing** - this is infrastructure-level work

### Testing Approach
- kubectl commands for pod/deployment/service status
- curl from within cluster (kubectl exec into gateway pod) for endpoint tests
- ssh for node-level verification (nvidia-smi, file checks)
- No automated test suite exists - all validation is manual commands

## Validation Concurrency

**Max concurrent validators**: 5
**Rationale**: Each validation is a lightweight kubectl/curl command. No heavy resource consumption per validator. The cluster is already running and accessible.

## Resource Cost Classification

| Surface | Memory per validator | CPU per validator | Notes |
|---------|---------------------|-------------------|-------|
| kubectl commands | ~50MB | Negligible | CLI tool only |
| curl from gateway pod | ~10MB | Negligible | Uses existing pod |
| ssh to nodes | ~20MB | Negligible | SSH session |
