# Akash Network Provider Assistant - Reorganized Skill

## Overview

Intelligent assistant for managing Akash Network provider deployments on Kubernetes clusters. Provides automated diagnostics, issue prioritization, and intelligent fix suggestions.

---

## Quick Health Checks

### `/akash check`
```bash
# Quick health check (provider status, helm release, resources)
/akash check
```

**Output Format:**
- Provider status and health
- Helm release status
- Resource usage and allocation
- Basic health indicators

---

### `/akash monitor`
```bash
# Real-time monitoring of provider metrics and logs
/akash monitor
```

**Output Format:**
- Live metrics dashboard
- Alerting and notifications
- Time-series data visualization
- Performance indicators

---

## Full Provider Audits

### `/akash audit`
```bash
# Full provider audit (12-category analysis with prioritization)
/akash audit
```

**Output Format:**
- **12-category analysis** (deployment, configuration, resources, networking, storage, RPC, bid engine, leases, attributes, metrics, security, optimization)
- **Prioritized issue list** with severity levels (P0, P1, P2, P3)
- Detailed impact analysis for each issue
- Recommended remediation steps
- Priority ranking by severity and impact

---

### `/akash explain`
```bash
# Generate detailed explanation of current state and issues
/akash explain
```

**Output Format:**
- **Markdown report** with issue descriptions
- Impact analysis for each problem
- Remediation steps and alternatives
- Root cause identification
- Actionable recommendations

---

## Auto-Fix Capabilities

### `/akash fix`
```bash
# Attempt automatic fixes for detected problems
/akash fix
```

**Output Format:**
- **Fix attempts** with status indicators (attempted/success/failure)
- **Success/failure reasons** for each attempt
- **Recommended fixes** based on cluster patterns
- **Preventive suggestions** for future prevention

---

## Detailed Diagnostics

### `/akash`
```bash
# Comprehensive provider health check and diagnostics
/akash
```

**Output Format:**
- **12-category comprehensive analysis**
- **Detailed issue reporting** with explanations
- **Root cause identification**
- **Actionable recommendations**
- **Severity rating** for each finding

---

## Usage Examples

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

---

## Technical Specifications

### Prerequisites
- **Node.js**: >= 18.0.0
- **Kubernetes**: kubectl configured with cluster access
- **Helm**: helm3 installed
- **Akash**: Provider deployed via official Helm chart
- **Namespace**: Provider must be in `akash-services` namespace
- **Access**: Read access to Kubernetes API, write access for auto-fix

### Output Formats
- Terminal: Formatted tables with color-coded severity levels
- Markdown: Structured reports for documentation
- JSON: Machine-readable output for automation
- Logs: Detailed diagnostic logs in `/var/log/akash-assistant/`

---

## Version
**1.0.0** | 2026-03-21

---

## See Also
- [Akash Provider Documentation](https://docs.akash.network/providers)
- [Helm Chart Reference](https://github.com/akash-network/provider/tree/main/charts/akash-provider)
- [Kubernetes Auditing Guide](/etc/nixos/docs/audit/README.md)