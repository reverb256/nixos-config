# Akash Assistant Training Guide

> For AI agents integrating the Akash Network Provider Assistant skill

## Overview

The Akash Assistant skill provides intelligent Kubernetes cluster management for Akash Network providers. This guide explains how AI agents can effectively use the skill.

## Skill Architecture

### Core Components

1. **Diagnostics Engine** (`src/diagnostics.js`)
   - Provider health checks
   - Hardware discovery (CPU, memory, GPU)
   - Cluster health monitoring
   - Storage and network validation

2. **Prioritization System** (`src/prioritizer.js`)
   - Issue scoring algorithm (base + impact + urgency)
   - Severity levels: P0 (critical) to P3 (low)
   - Automated ranking and categorization

3. **Explanation Generator** (`src/explainer.js`)
   - Markdown reports for humans
   - JSON output for AI agents
   - ASCII topology diagrams
   - Topic-based explanations

4. **Auto-Fix Module** (`src/auto-fix.js`)
   - Automatic fixes (pod restart, scaling)
   - Permission-required fixes (config changes)
   - Safe kubectl execution

5. **Knowledge Base** (`src/knowledge.js`)
   - Pattern detection (3+ occurrences)
   - Built-in Akash documentation
   - Baseline establishment
   - Learning from history

## Usage Patterns

### Basic Health Check

```javascript
const { handleCommand } = require('./src/index.js');

// Quick health check
const result = await handleCommand('check', {
  namespace: 'akash-services'
});
```

### Full Audit with Auto-Fix

```javascript
// Full audit with automatic fixes
const audit = await handleCommand('audit', {
  namespace: 'akash-services',
  autoFix: true  // Enable automatic fixes
});
```

### Topic Explanations

```javascript
// Get GPU explanation
const gpuInfo = await handleCommand('explain', {
  topic: 'gpu',
  namespace: 'akash-services'
});
```

## Output Formats

### JSON Output (for AI agents)

```javascript
const result = await handleCommand('check', {
  json: true  // Returns structured JSON
});

// Structure:
{
  "clusterHealth": { ... },
  "provider": { ... },
  "hardware": { ... },
  "issues": [
    {
      "id": "gpu-not-detected",
      "severity": "critical",
      "category": "hardware",
      "title": "GPU Not Detected",
      "recommendation": "...",
      "hasFix": true,
      "autoFix": false,
      "fixAction": "provider-config"
    }
  ],
  "summary": { ... }
}
```

### Markdown Output (for humans)

```javascript
const result = await handleCommand('check', {
  json: false  // Returns formatted markdown
});
```

## Best Practices

### 1. Always Check Cluster Health First

```javascript
const health = await handleCommand('check');
if (health.summary.critical > 0) {
  // Handle critical issues first
}
```

### 2. Use Pattern Detection for Recurring Issues

```javascript
const { detectPatterns } = require('./src/knowledge');
const patterns = detectPatterns(issues, history);
// patterns.recurring: Issues appearing 3+ times
```

### 3. Respect Permission System

```javascript
const fix = await attemptAutoFix(issue, { autoFix: false });
if (fix.requiredPermission) {
  // Ask user before proceeding
  console.log(`Requires approval: ${fix.reason}`);
}
```

### 4. Monitor Resource Utilization

```javascript
const gpu = await checkGPUInventory();
if (gpu.utilization > 90) {
  // Warn about high GPU utilization
}
```

## Integration Example

```javascript
const { handleCommand } = require('./src/index.js');

async function monitorAkashProvider() {
  // Run full diagnostics
  const audit = await handleCommand('audit', {
    namespace: 'akash-services',
    json: true
  });

  // Prioritize issues
  const critical = audit.issues.filter(i => i.severity === 'critical');
  const high = audit.issues.filter(i => i.severity === 'high');

  // Attempt automatic fixes for safe issues
  for (const issue of audit.issues) {
    if (issue.autoFix && issue.severity !== 'critical') {
      await handleCommand('fix', {
        issue: issue,
        autoFix: true
      });
    }
  }

  return audit;
}
```

## Error Handling

All functions return structured error objects:

```javascript
const result = await handleCommand('check');
if (!result.success) {
  console.error('Diagnostics failed:', result.error);
  // Handle error gracefully
}
```

## Testing

```bash
# Run unit tests
npm test

# Run integration tests
./tests/cluster-test.sh

# Test with real cluster
AKASH_NAMESPACE=akash-services node src/index.js check
```

## Troubleshooting

### Issue: kubectl commands fail
**Solution**: Verify kubectl is configured: `kubectl get nodes`

### Issue: Provider pod not found
**Solution**: Check namespace: `kubectl get pods -n akash-services`

### Issue: GPU not detected
**Solution**: Verify GPU drivers: `nvidia-smi` or `rocminfo`

## Additional Resources

- README.md: User-facing documentation
- CHANGELOG.md: Version history
- Implementation Plan: docs/plans/2026-03-21-akash-assistant-implementation.md
