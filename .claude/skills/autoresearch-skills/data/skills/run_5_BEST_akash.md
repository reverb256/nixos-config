# Akash Network Provider Assistant

## Overview
Intelligent assistant for managing Akash Network provider deployments on Kubernetes clusters. Provides automated diagnostics, issue prioritization, and intelligent fix suggestions.

## Use When
- Managing Akash Network provider deployments
- Troubleshooting provider configuration issues
- Monitoring provider health and performance
- Optimizing provider resource allocation
- Investigating provider-tenant communication problems

## Commands

| Command | Description |
|---------|-------------|
| `/akash` | Run comprehensive provider health check and diagnostics |
| `/akash check` | Quick health check (provider status, helm release, resources) |
| `/akash audit` | Full provider audit (12-category analysis with prioritization) |
| `/akash fix` | Attempt automatic fixes for detected issues |
| `/akash explain` | Generate detailed explanation of current state and issues |
| `/akash monitor` | Real-time monitoring of provider metrics and logs |

## What It Does

- **Multi-category diagnostics**: Analyzes 12 categories including deployment, configuration, resources, networking, storage, RPC, bid engine, leases, attributes, metrics, security, and optimization
- **Intelligent prioritization**: Ranks issues by severity (P0-P3) with impact analysis
- **Auto-fix capabilities**: Automatically attempts fixes for common issues (resource limits, missing labels, stuck deployments)
- **Contextual explanations**: Generates human-readable reports with issue descriptions, impacts, and remediation steps
- **Learning system**: Builds knowledge base from successful fixes and adapts to cluster-specific patterns

## Output Formats

- **Terminal**: Formatted tables with color-coded severity levels
- **Markdown**: Structured reports for documentation
- **JSON**: Machine-readable output for automation
- **Logs**: Detailed diagnostic logs in `/var/log/akash-assistant/`

## Requirements

- **Node.js**: >=18.0.0
- **Kubernetes**: kubectl configured with cluster access
- **Helm**: helm3 installed
- **Akash**: Provider deployed via official Helm chart
- **Namespace**: Provider must be in `akash-services` namespace
- **Access**: Read access to Kubernetes API, write access for auto-fix

## Examples

### Quick Health Check
```bash
# Verify provider is running and responsive
/akash check
# Output: Provider status, helm release status, resource usage
```

### Full Audit with Prioritization
```bash
# Run comprehensive 12-category audit
/akash audit
# Output: Prioritized issue list with P0-P3 severity levels
```

### Auto-Fix Detected Issues
```bash
# Attempt automatic fixes for detected problems
/akash fix
# Output: Fix attempts with success/failure status
```

### Generate Explanation Report
```bash
# Get detailed explanation of current state
/akash explain
# Output: Markdown report with issue descriptions and remediation
```

### Monitor Provider Metrics
```bash
# Real-time monitoring of provider health
/akash monitor
# Output: Live metrics dashboard with alerts
```

## Version
**1.0.0** | 2026-03-21

## See Also
- [Akash Provider Documentation](https://docs.akash.network/providers)
- [Helm Chart Reference](https://github.com/akash-network/provider/tree/main/charts/akash-provider)
- [Kubernetes Auditing Guide](/etc/nixos/docs/audit/README.md)
