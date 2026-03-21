# Akash Assistant Skill Design Document
**Project**: Akash Network Provider Assistant
**Date**: 2026-03-21
**Status**: Design Approved - Ready for Implementation
**Target Users**: AI Agents (Claude, OpenCode) assisting with Akash operations

---

## Executive Summary

The **Akash Assistant** is a comprehensive, intelligent skill for managing Akash Network provider operations on a NixOS Kubernetes cluster. It combines automated diagnostics, issue prioritization, plain-language explanations, visual topology displays, and auto-fix capabilities into a single unified entry point.

**Key Value**: Makes Akash provider operations accessible for newcomers while providing powerful automation for experienced operators. Designed for AI agents to use during interactive TUI sessions, with output formats suitable for both agent parsing and human consumption.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Core Components](#core-components)
4. [Data Flow](#data-flow)
5. [Output Formats](#output-formats)
6. [Error Handling & Blind Spots](#error-handling--blind-spots)
7. [Testing Strategy](#testing-strategy)
8. [Implementation Plan](#implementation-plan)

---

## Overview

### Purpose

Enable AI agents (Claude, OpenCode, etc.) to:
- Automatically diagnose Akash provider health issues
- Explain cluster state in plain language with visuals
- Fix common issues automatically
- Teach users about Akash Network concepts
- Provide actionable recommendations

### Scope

**In Scope**:
- Akash provider health monitoring
- Hardware discovery validation
- GPU inventory management
- Lease lifecycle monitoring
- Blockchain connectivity
- Resource utilization tracking
- Issue prioritization and remediation

**Out of Scope**:
- Akash tenant management (deploying workloads)
- Lease bidding strategy optimization
- Multi-cluster management
- Akash marketplace operations

### Target Audience

**Primary**: AI agents assisting users during interactive sessions
**Secondary**: Cluster operators learning Akash Network

---

## Architecture

### Entry Points

**Primary Command**: `/akash` or `/akash help`

**Specialized Modes**:
- `/akash check` - Quick health check
- `/akash audit` - Full diagnostic audit
- `/akash fix` - Auto-fix issues
- `/akash explain <topic>` - Learning mode
- `/akash monitor` - Continuous monitoring

### System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     AI Agent (Claude/OpenCode)                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Akash Assistant Skill                    │
├─────────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Diagnostics  │→ │Prioritization│→ │Explanation  │      │
│  │   Engine     │  │   System     │  │  Generator   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         ↓                  ↓                  ↓              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Auto-Fix    │← │  Knowledge   │← │ Visual       │      │
│  │   Module     │  │    Base      │  │   Renderer   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                               │
└───────────────┬───────────────────────────────────────────────────┘
                │
                ▼
        ┌───────────────┐
        │ Kubernetes   │
        │   Cluster    │
        │  (Read Only)  │
        └───────────────┘
```

### Data Sources

**Kubernetes API**:
- Provider pods: `kubectl get pods -n akash-services`
- Hardware discovery: `kubectl get pods -l app.kubernetes.io/name=inventory`
- Node resources: `kubectl describe node <node>`

**Provider Logs**:
- Provider logs: `kubectl logs -n akash-services akash-provider-0`
- Operator logs: `kubectl logs -n akash-services operator-*`
- Blockchain node: `kubectl logs -n akash-services akash-node-0`

**Configuration**:
- Provider inventory: Provider logs /metrics endpoint
- ConfigMaps: `kubectl get configmap -n akash-services operator-inventory`
- ResourceQuotas: `kubectl get resourcequota -n akash-services`

---

## Core Components

### Component 1: Diagnostics Engine

**Purpose**: Comprehensive health checks across all Akash provider components

**Checks Performed**:

1. **Provider Health**
   - Provider pod running?
   - Container restart count
   - Log errors (last 50 lines)
   - Uptime (from pod age)

2. **Hardware Discovery**
   - All 4 nodes detected?
   - Hardware discovery pods running?
   - Node resources reported correctly?
   - Inventory matches actual cluster state?

3. **GPU Inventory**
   - Total GPUs in provider inventory
   - NVIDIA vs AMD breakdown
   - GPU count accuracy (compare with `kubectl describe node`)
   - Identify discrepancies

4. **Lease Status**
   - Active lease count
   - GPU allocation
   - Lease lifecycle (pending, active, terminating)
   - Orphaned lease pods

5. **Network Connectivity**
   - Provider → blockchain (RPC reachable?)
   - DNS resolution working?
   - Inter-pod communication (provider → operators)
   - External connectivity (for bidding)

6. **Blockchain Sync**
   - Blockchain node syncing?
   - Peer connections established?
   - Block height current?

**Implementation**:
```javascript
async function runDiagnostics(cluster) {
  const results = {
    provider: await checkProviderHealth(cluster),
    hardware: await checkHardwareDiscovery(cluster),
    gpus: await checkGPUInventory(cluster),
    leases: await checkLeaseStatus(cluster),
    network: await checkNetworkConnectivity(cluster),
    blockchain: await checkBlockchainSync(cluster)
  };

  return results;
}
```

### Component 2: Prioritization System

**Purpose**: Rank issues by severity and impact

**Severity Levels**:

| Severity | Criteria | Examples |
|----------|----------|----------|
| **Critical** | Provider down, no bidding | Provider crashed, blockchain sync lost |
| **High** | Major functionality broken | Hardware discovery failed, GPU count wrong |
| **Medium** | Partial degradation | Resource warnings, network issues |
| **Low** | Optimizations | Config cleanup, documentation updates |

**Prioritization Algorithm**:
```javascript
function prioritizeIssue(issue) {
  let score = 0;

  // Severity base score
  score += { critical: 100, high: 50, medium: 20, low: 5 }[issue.severity];

  // Impact modifier
  if (issue.affectsRevenue) score += 20;
  if (issue.affectsMultipleNodes) score += 15;
  if (issue.blocksNewLeases) score += 25;

  // Urgency modifier
  if (issue.degradingOverTime) score += 10;
  if (issue.userComplaints) score += 15;

  return score;
}
```

**Output Format**:
```json
{
  "issues": [
    {
      "id": "gpu-count-mismatch",
      "severity": "high",
      "score": 65,
      "title": "GPU Count Mismatch",
      "category": "attribute_validation",
      "affectsRevenue": true,
      "blocksNewLeases": false
    }
  ]
}
```

### Component 3: Explanation Generator

**Purpose**: Create human-readable, plain-language explanations with visuals

**Capabilities**:

1. **Plain Language Summaries**
   - Technical terms explained simply
   - Context provided for issues
   - Actionable recommendations

2. **Visual Topology Diagrams**
   - ASCII art cluster layout
   - Color-coded health indicators
   - Resource allocation visualization

3. **Contextual Explanations**
   - "Why this matters" sections
   - "What happens next" information
   - Links to relevant documentation

**Example Outputs**:

*Plain Language*:
```
Your provider is healthy and actively bidding on leases.
It has 5 NVIDIA GPUs available (2 are currently in use).
All 4 nodes are detected and operational.
```

*Visual Diagram*:
```
Cluster Topology:
┌────────────────────────────────────────┐
│  forge    [████████████] 2 NVIDIA GPUs  │
│  nexus    [████████] 1 NVIDIA GPU      │
│  sentry   [no NVIDIA GPUs]                │
│  zephyr   [████████████] 2 NVIDIA GPUs  │
└────────────────────────────────────────┘

GPU Allocation:
Total: ████████████████████ 5 GPUs
Used:  ████████ 2 GPUs (40%)
Free: █████████████ 3 GPUs (60%)
```

### Component 4: Auto-Fix Module

**Purpose**: Automatically fix common issues, request permission for complex ones

**Fix Categories**:

**Automatic Fixes** (No permission needed):
- Restart stuck provider pods
- Clean up failed/terminated pods
- Apply known configuration patches
- Restart hardware discovery pods

**Permission-Required Fixes** (Asks first):
- Modify provider configuration
- Adjust resource limits
- Restart services (may interrupt leases)
- Update ConfigMaps
- Rollback deployments

**Decision Flow**:
```javascript
async function attemptAutoFix(issue) {
  // Check if fix is safe and automatic
  if (issue.autoFix && issue.risk === 'low') {
    const result = await executeFix(issue);
    return { success: result, action: 'automatic' };
  }

  // Check if fix needs permission
  if (issue.hasFix && issue.risk !== 'critical') {
    const response = await requestPermission({
      issue: issue.title,
      action: issue.recommendation,
      risk: issue.risk,
      estimatedTime: issue.estimatedTime
    });

    if (response.approved) {
      const result = await executeFix(issue);
      return { success: result, action: 'user-approved' };
    }

    return { success: false, action: 'user-declined' };
  }

  return { success: false, action: 'no-fix-available' };
}
```

### Component 5: Knowledge Base

**Purpose**: Built-in Akash documentation + cluster learning

**Knowledge Sources**:

1. **Built-in Documentation**
   - Akash Network provider documentation
   - Kubernetes best practices
   - NixOS-specific considerations
   - Common issues and solutions

2. **Cluster History**
   - Past issues and resolutions
   - Configuration changes over time
   - Resource utilization trends
   - Performance baselines

3. **Learning System**
   - Remembers "normal" cluster state
   - Tracks recurring issues
   - Builds patterns from your audits
   - Improves recommendations over time

**Example Learning**:
```yaml
Initial State:
  - GPU counting: Known issue (AMD on sentry)
  - Provider uptime baseline: 99%+
  - Typical resource usage: 40% GPU utilization

After 1 Week:
  - Learned: Provider usually restarts on Tuesdays (maintenance)
  - Learned: GPU utilization spikes during evening hours
  - Learned: Flannel IP exhaustion happens when >7000 pods

Improvements:
  - Tuesday checks: Warn about scheduled maintenance
  - Evening alerts: Monitor for GPU exhaustion
  - Pod count alerts: Warn before 6000 pods
```

---

## Data Flow

### Execution Flow

```
1. Agent Invokes Skill
   ↓
2. Skill Contextualizes Request
   - "check" → Quick diagnostics
   - "audit" → Full analysis
   - "explain gpu" → Focused topic
   ↓
3. Diagnostics Engine Executes
   - Queries Kubernetes API
   - Checks provider logs
   - Validates cluster state
   ↓
4. Prioritization System Ranks Issues
   - Categorizes by severity
   - Scores by impact
   - Sorts by priority
   ↓
5. Explanation Generator Creates Output
   - Plain-language summary
   - Visual topology diagram
   - Detailed findings
   - Recommendations
   ↓
6. Auto-Fix Module Evaluates
   - Identify automatic fixes
   - Request permission for complex fixes
   - Execute approved fixes
   ↓
7. Dual Output Generated
   - JSON for agents (parseable)
   - Markdown for humans (readable)
   ↓
8. Knowledge Base Updated
   - Store cluster state
   - Learn patterns
   - Improve future recommendations
```

### Data Sources Integration

**Kubernetes API Queries**:
```bash
# Provider status
kubectl get pods -n akash-services -l app.kubernetes.io/name=akash-provider

# Hardware discovery
kubectl get pods -n akash-services -l app.kubernetes.io/name=inventory

# Node resources
kubectl describe node | grep -A 5 "Allocated resources"

# Provider logs
kubectl logs -n akash-services akash-provider-0 --tail=50
```

**Data Processing Pipeline**:
```
Raw Data → Validation → Normalization → Analysis → Prioritization → Output
```

---

## Output Formats

### Format 1: Structured JSON (For AI Agents)

**Schema**:
```json
{
  "metadata": {
    "timestamp": "ISO-8601",
    "cluster_name": "string",
    "check_duration_seconds": "number",
    "skill_version": "string"
  },
  "cluster_state": {
    "provider": {
      "status": "healthy|degraded|down",
      "pod_running": "boolean",
      "bidding_active": "boolean",
      "blockchain_synced": "boolean",
      "uptime_hours": "number",
      "restart_count": "number"
    },
    "nodes": {
      "total": "number",
      "ready": "number",
      "details": [
        {
          "name": "string",
          "ready": "boolean",
          "gpus": {
            "nvidia": "number",
            "amd": "number",
            "total": "number"
          },
          "resources": {
            "cpu_allocatable": "number",
            "memory_allocatable": "bytes"
          }
        }
      ]
    },
    "inventory": {
      "total_allocatable": {
        "cpu": "millicores",
        "gpu": "number",
        "memory": "bytes"
      },
      "total_available": {
        "cpu": "millicores",
        "gpu": "number",
        "memory": "bytes"
      },
      "active_leases": "number"
    }
  },
  "issues": [
    {
      "id": "string",
      "severity": "critical|high|medium|low",
      "score": "number",
      "category": "string",
      "title": "string",
      "description": "string",
      "details": "object",
      "recommendation": "string",
      "auto_fix_available": "boolean",
      "priority": "number",
      "estimated_fix_time": "minutes",
      "risk": "low|medium|high|critical"
    }
  ],
  "recommendations": [
    {
      "action": "string",
      "title": "string",
      "description": "string",
      "urgency": "immediate|soon|eventually"
    }
  ],
  "visual_topology": {
    "type": "ascii_diagram|mermaid",
    "diagram": "string"
  },
  "learning_insights": {
    "baselines_established": "boolean",
    "patterns_detected": ["string"],
    "recommendations_improved": "boolean"
  }
}
```

### Format 2: Human-Readable Markdown (For Users)

**Template**:
```markdown
# Akash Provider Health Report
Generated: [Timestamp]
Check Duration: [Duration]

## Executive Summary [Emoji]
[One-line summary]

## Cluster Topology
[Visual ASCII diagram]

## Detailed Findings
### Provider Status [Emoji]
[Details]

### Issues Found
[Issue 1]
[Issue 2]

## Resource Allocation
[Table]

## Active Leases
[Lease details]

## Recommendations
1. [Recommendation 1]
2. [Recommendation 2]

## Learning Insights
[What the skill learned]
```

### Format 3: Conversational (Interactive)

**Example Dialogue**:
```
User: "/akash why is my gpu count wrong?"
Skill: "The provider shows 6 GPUs because sentry's AMD RX 5600XT is being
        counted as NVIDIA. Your cluster actually has 5 NVIDIA GPUs:

        • forge: 2x NVIDIA RTX 4060
        • nexus: 1x NVIDIA RTX 3060 Ti
        • zephyr: 2x NVIDIA RTX 3090

        Want me to show you how to fix this?"

User: "Yes please"
Skill: "To fix this, update the operator-inventory ConfigMap to add sentry to the
        exclusion list. This will prevent its AMD GPU from being counted.

        Shall I show you the exact kubectl command to run?"
```

---

## Error Handling & Blind Spots

### Comprehensive Coverage Matrix

| Category | Checks | Error Handling |
|----------|--------|----------------|
| **Node Health** | Reachability, readiness, resource pressure, network partition, rebuild conflicts | Graceful degradation, cached data |
| **Blockchain** | Sync status, RPC connectivity, peer connections, gas/fees | Fallback to cached state, manual recovery guide |
| **Lease Lifecycle** | Pending leases, stuck pods, orphaned pods, deployment failures | Auto-cleanup, manual intervention guide |
| **Provider Wallet** | Token balance, accessibility, locked status | Alert and wait for manual intervention |
| **Attributes** | GPU counts, CPU/memory accuracy, storage, node exclusion | Document discrepancies, monitor only |
| **Updates** | Active rebuilds, deployments, restarts, config drift | Warn about conflicts, recommend waiting |
| **Certificates** | Expiration, validation, auth failures | Alert before expiry, provide renewal guide |
| **Resources** | Disk space, memory pressure, CPU throttling, PID exhaustion | Alert thresholds, auto-cleanup |
| **Network** | DNS issues, firewall rules, inter-node connectivity | Test connectivity, provide fix commands |

### Fallback Strategy

```javascript
async function executeWithFallback(diagnosticFunction) {
  try {
    // Primary: Full automated check
    return await diagnosticFunction();
  } catch (error) {
    if (error.type === 'kubernetes_unreachable') {
      // Fallback 1: Use cached data
      const cached = await loadCachedState();
      if (cached && isRecent(cached, 15)) {
        return {
          success: true,
          data: cached,
          source: 'cache',
          warning: 'Using cached data (cluster unreachable)'
        };
      }
    }

    // Fallback 2: Manual investigation guide
    return {
      success: false,
      data: null,
      source: 'manual',
      guide: generateManualInvestigationGuide(error)
    };
  }
}
```

### Error Recovery

**Automatic Recovery**:
- Retry transient failures (network timeouts, API rate limits)
- Restart stuck pods (with permission)
- Clear known error states

**Manual Recovery Guidance**:
- Step-by-step troubleshooting instructions
- kubectl commands to run manually
- Logs to check
- When to escalate

---

## Testing Strategy

### Unit Testing

**Diagnostics Engine**:
```javascript
describe('Diagnostics Engine', () => {
  it('should detect provider down state', async () => {
    const mock = {
      pods: [{ status: 'Failed' }]
    };
    const result = await checkProviderHealth(mock);
    expect(result.status).toBe('down');
  });

  it('should validate GPU inventory', async () => {
    const mock = {
      providerInventory: { gpu: 6 },
      actualGPUs: { nvidia: 5, amd: 1 }
    };
    const result = await checkGPUInventory(mock);
    expect(result.discrepancies).toHaveLength(1);
  });
});
```

**Prioritization System**:
```javascript
describe('Prioritization', () => {
  it('should prioritize provider down over GPU mismatch', () => {
    const issues = [
      { severity: 'critical', category: 'provider_down' },
      { severity: 'high', category: 'gpu_mismatch' }
    ];
    const ranked = prioritizeIssues(issues);
    expect(ranked[0].category).toBe('provider_down');
  });
});
```

### Integration Testing

**Test Scenarios**:

1. **Healthy Cluster**: No issues expected
2. **Single Critical Issue**: Provider down
3. **Multiple High Issues**: GPU count + network
4. **Edge Cases**: Node partition, resource exhaustion
5. **Known Issues**: GPU counting (from your cluster)

**Integration Test Framework**:
```javascript
describe('Akash Assistant Integration', () => {
  it('should analyze real cluster and produce report', async () => {
    const result = await akashAssistant.analyze();
    expect(result).toHaveProperty('cluster_state');
    expect(result).toHaveProperty('issues');
    expect(result).toHaveProperty('recommendations');
  });
});
```

### Mock Cluster Testing

For testing without affecting production:

```bash
# Create test namespace
kubectl create namespace akash-test

# Deploy mock provider
kubectl apply -f test-fixtures/mock-provider.yaml

# Run skill against test cluster
/akash audit --namespace=akash-test

# Verify results
kubectl delete namespace akash-test
```

---

## Implementation Plan

### Phase 1: Core Diagnostics (Week 1)
**Tasks**:
1. Set up skill structure
2. Implement basic health checks
3. Test with real cluster
4. Generate initial reports

**Deliverable**:
- `/akash` command works
- Basic health checks functional
- Simple text output

### Phase 2: Intelligence Features (Week 2)
**Tasks**:
1. Add prioritization system
2. Implement auto-fix module
3. Create visual diagrams
4. Build knowledge base

**Deliverable**:
- Issue ranking works
- Automatic fixes operational
- Visual topology displays
- Learning system active

### Phase 3: Advanced Features (Week 3)
**Tasks**:
1. Add conversational mode
2. Implement comprehensive blind spot coverage
3. Build learning system
4. Create tutorials

**Deliverable**:
- Interactive conversations work
- All edge cases handled
- Cluster learning operational
- Educational content complete

### Phase 4: Polish & Deploy (Week 4)
**Tasks**:
1. Performance optimization
2. Error handling refinement
3. Documentation completion
4. Agent integration testing

**Deliverable**:
- Production-ready skill
- Agent integration verified
- Full documentation
- Training for agents

---

## Success Criteria

### Functional Requirements
- ✅ Accurate health checks across all Akash components
- ✅ Issues prioritized correctly by severity
- ✅ Plain-language explanations clear for newcomers
- ✅ Visual diagrams helpful and accurate
- ✅ Auto-fixes work safely (with permission)
- ✅ Knowledge base improves over time

### Non-Functional Requirements
- ✅ Response time < 30 seconds for full check
- ✅ Handles cluster errors gracefully
- ✅ Works with Serena tools and justfile
- ✅ Output parseable by AI agents
- ✅ Learning from cluster history

### Quality Requirements
- ✅ Zero false positives in critical issues
- ✅ No automatic fixes without user approval (high-risk)
- ✅ All recommendations actionable
- ✅ Errors explained clearly with recovery steps

---

## Design Decisions & Trade-offs

### Decision 1: Unified vs. Modular
**Choice**: Unified with intelligent routing
**Rationale**: Easier for agents to use, better context awareness
**Trade-off**: More complex to maintain than separate commands

### Decision 2: Auto-Fix Permissions
**Choice**: Hybrid (automatic for low-risk, permission for high-risk)
**Rationale**: Safety while maintaining automation benefits
**Trade-off**: Requires more logic than fully automatic

### Decision 3: Output Format
**Choice**: Dual format (JSON + Markdown)
**Rationale**: Serves both agents and humans
**Trade-off**: Larger output, longer generation time

### Decision 4: Knowledge Base
**Choice**: Learning from cluster history + built-in docs
**Rationale**: Improves over time, contextually relevant
**Trade-off**: Requires storage, more complex

---

## Open Questions

1. **Storage**: Where to store learned patterns? (File-based, database, in-memory only?)
2. **Retention**: How long to keep cluster history? (Privacy concerns?)
3. **Updates**: How to update built-in Akash documentation? (Manual, auto-fetch?)
4. **Multi-Cluster**: Should this work on multiple clusters? (Future consideration)

---

## Appendix: Quick Reference

### Example Usage

**Agent Usage**:
```javascript
// In agent code
const result = await skill.invoke('akash');
const issues = result.issues.filter(i => i.severity === 'critical');
```

**Direct Usage**:
```bash
# Quick health check
/akash

# Full audit
/akash audit

# Explain specific topic
/akash explain leases

# Fix issues
/akash fix
```

### Key Files

- `SKILL.md` - Skill metadata and invocation
- `src/diagnostics.js` - Health check logic
- `src/prioritizer.js` - Issue ranking
- `src/explainer.js` - Output generation
- `src/auto-fix.js` - Fix automation
- `src/knowledge.js` - Learning system
- `docs/akash-reference.md` - Built-in documentation

---

**Design Version**: 1.0
**Status**: Approved - Ready for Implementation
**Next Step**: Invoke `/skill-creator` to create skill structure
**Target Implementation**: 4 weeks
**Maintainer**: Cluster Operations Team
