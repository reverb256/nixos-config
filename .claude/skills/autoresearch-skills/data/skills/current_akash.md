# Akash Network Provider Assistant

## Overview
Intelligent assistant for managing Akash Network provider deployments on Kubernetes clusters. Provides automated diagnostics, issue prioritization, and intelligent fix suggestions with strict safety constraints.

## Use When
- Diagnosing why a provider is not bidding on leases
- Troubleshooting Helm chart deployment failures in `akash-services`
- Verifying provider readiness before mainnet activation
- Investigating "Provider Not Found" or connectivity errors from tenants
- Analyzing resource limits causing provider pod evictions
- Auditing security settings (RPC endpoints, bid engine exposure)

## Commands

| Command | Description |
|---------|-------------|
| `/akash` | Execute full diagnostic workflow (alias for `/akash audit` followed by `/akash explain`) |
| `/akash check` | Surface-level health check: validates Pod status (Running/Ready), Helm release state, and immediate resource availability. Does not perform deep inspection. |
| `/akash audit` | Execute deep-dive inspection across 12 distinct categories. Outputs JSON with severity rankings (P0-P3). |
| `/akash fix` | Attempt remediation for **P0 and P1** issues only. Requires explicit confirmation before modifying cluster state. |
| `/akash explain` | Generate a detailed Markdown report interpreting audit results, specific to the detected issues and their business impact. |
| `/akash monitor` | Stream live metrics (CPU/Mem %, Active Bids, RPC Latency) for the provider pod. Defaults to 60-second interval. |

## What It Does

### 1. Multi-category Diagnostics
Performs specific checks in the following 12 categories:
- **Deployment**: Pod replica status, image versions, restart counts
- **Configuration**: Helm values validation against current environment
- **Resources**: CPU/Memory requests vs limits vs actual usage
- **Networking**: Ingress status, port exposure (8443/30000), DNS resolution
- **Storage**: Persistent Volume Claims (PVC) binding status
- **RPC**: Connectivity to blockchain RPC nodes, sync status
- **Bid Engine**: Logs analysis for bid submission errors
- **Leases**: Active lease count and deployment statuses
- **Attributes**: Provider attributes matching cluster capabilities
- **Metrics**: Status of `akash-provider` metrics endpoint
- **Security**: Open ports, secret exposure, TLS configuration
- **Optimization**: Resource over-provisioning or under-utilization

### 2. Intelligent Prioritization
Rank issues based on defined severity levels:
- **P0 (Critical)**: Provider is down, not bidding, or unreachable. Immediate action required.
- **P1 (High)**: Functionality degraded (e.g., high rejection rates, failing RPC connections).
- **P2 (Medium)**: Warnings present, potential future instability (e.g., resource pressure).
- **P3 (Low)**: Optimization opportunities or cosmetic inconsistencies.

### 3. Auto-fix Capabilities (Scoped)
**Scope**: Only attempts fixes for P0/P1 issues related to:
- Resource limit adjustments (increasing limits if OOMKilled)
- Missing Kubernetes labels/annotations required for discovery
- Restarting stuck pods (CrashLoopBackOff > 5 mins)
- Re-applying drifted Helm configurations (dry-run first)

**Safety Constraints**:
- **Never** deletes Persistent Volumes or Lease data.
- **Never** modifies private keys or `chain-id`.
- **Never** destroys active tenant deployments.
- Requires user confirmation (Y/N) before executing `kubectl apply` or `helm upgrade`.

### 4. Contextual Explanations
Generates human-readable reports linking technical errors (e.g., `ErrInsufficientFunds`) to specific remediation actions (e.g., "Check wallet balance and fund provider address").

### 5. Historical Context
Checks `/var/log/akash-assistant/history.json` to avoid suggesting fixes that were previously attempted and failed within the last 24 hours.

## Output Formats

- **Terminal**: Color-coded tables (Red=P0, Yellow=P1, Green=Healthy)
- **Markdown**: Structured reports with code blocks for CLI commands
- **JSON**: Strict schema including `issue_id`, `category`, `severity`, `message`, `remediation`
- **Logs**: Detailed operational logs stored in `/var/log/akash-assistant/`

## Requirements

- **Node.js**: >=18.0.0
- **Kubernetes**: `kubectl` v1.27+ configured and context set to target cluster
- **Helm**: v3.0+ installed
- **Akash**: Provider deployed via `akash-network/akash-provider` Helm chart
- **Namespace**: Operations strictly scoped to `akash-services` namespace
- **Cluster Role**: ServiceAccount must have `cluster-admin` or equivalent `read/write` permissions on Deployments, Services, and ConfigMaps
- **Wallet**: Provider wallet address imported for RPC balance checks

## Examples

### Quick Health Check
```bash
# Verify provider is running and responsive
/akash check
# Output: 
# ✅ Pod: akash-provider-6b8c9d (Running)
# ✅ Helm: akash-provider (deployed)
# ⚠️  Resources: CPU at 85%
```

### Full Audit with Prioritization
```bash
# Run comprehensive 12-category audit
/akash audit
# Output: JSON array of issues sorted by P0-P3
# [{"id": "RPC-001", "severity": "P0", "message": "RPC endpoint unreachable..."}]
```

### Safe Auto-Fix
```bash
# Attempt automatic fixes for P0/P1 issues
/akash fix
# System: Detected P0 issue: Memory limits too low.
# Proposed Fix: Update limits to 4Gi/4Gi. Proceed? [y/N]
```

### Generate Explanation Report
```bash
# Get detailed explanation of current state
/akash explain
# Output: 
# ## Provider Status: Critical
# The bid engine is failing to submit bids due to RPC timeout...
```

### Monitor Provider Metrics
```bash
# Real-time monitoring of provider health (60s duration)
/akash monitor
# Output: Live dashboard updating every 5s:
# [BIDS: 0] [CPU: 45%] [RPC_LATENCY: 120ms]
```

## Version
**1.0.0** | 2026-03-21

## See Also
- [Akash Provider Documentation](https://docs.akash.network/providers)
- [Helm Chart Reference](https://github.com/akash-network/provider/tree/main/charts/akash-provider)
- [Kubernetes Auditing Guide](/etc/nixos/docs/audit/README.md)