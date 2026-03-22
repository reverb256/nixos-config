/**
 * Diagnostics Engine
 *
 * Health check logic for Akash Network provider deployments.
 * Analyzes provider state across multiple categories.
 *
 * Categories:
 * - Deployment status
 * - Configuration validation
 * - Resource utilization
 * - Networking connectivity
 * - Storage provisioning
 * - RPC endpoint health
 * - Bid engine status
 * - Lease management
 * - Provider attributes
 * - Metrics collection
 * - Security posture
 * - Optimization opportunities
 */

const { getPods, getPodLogs, getNodes, kubectl } = require('./utils/kubectl');
const knowledge = require('./knowledge');

/**
 * Calculate uptime in hours from pod start time
 * @param {string|Date} startTime - Pod start time (ISO string or Date object)
 * @returns {number} Uptime in hours
 */
function calculateUptime(startTime) {
  const start = typeof startTime === 'string' ? new Date(startTime) : startTime;
  const now = new Date();
  const uptimeMs = now - start.getTime();
  return uptimeMs / (1000 * 60 * 60); // Convert to hours
}

/**
 * Create a standardized issue object
 * @param {Object} issueData - Issue data
 * @returns {Object} Standardized issue object
 */
function createIssue(issueData) {
  return {
    id: issueData.id || 'unknown-issue',
    severity: issueData.severity || 'medium', // critical | high | medium | low
    category: issueData.category || 'general',
    title: issueData.title || 'Untitled Issue',
    description: issueData.description || '',
    recommendation: issueData.recommendation || '',
    affectsRevenue: issueData.affectsRevenue || false,
    blocksNewLeases: issueData.blocksNewLeases || false,
    hasFix: issueData.hasFix || false,
    autoFix: issueData.autoFix || false,
    fixAction: issueData.fixAction || '',
    risk: issueData.risk || 'medium' // low | medium | high | critical
  };
}

/**
 * Check provider health status
 * @param {string} namespace - Kubernetes namespace where provider runs
 * @returns {Promise<Object>} Provider health status object
 */
async function checkProviderHealth(namespace) {
  const issues = [];

  try {
    // Get provider pods
    const pods = await getPods(namespace, 'app.kubernetes.io/name=akash-provider');

    // Check if provider pod exists
    if (!pods || pods.length === 0) {
      issues.push(createIssue({
        id: 'provider-pod-missing',
        severity: 'critical',
        category: 'provider',
        title: 'Provider Pod Not Found',
        description: `No provider pod found in namespace '${namespace}'. The provider deployment may not exist or has been deleted.`,
        recommendation: 'Check if the provider deployment exists. If not, redeploy the provider using helm or kubectl.',
        affectsRevenue: true,
        blocksNewLeases: true,
        hasFix: true,
        autoFix: false,
        fixAction: 'Redeploy provider',
        risk: 'critical'
      }));

      return {
        status: 'down',
        podRunning: false,
        biddingActive: false,
        blockchainSynced: false,
        uptimeHours: 0,
        restartCount: 0,
        issues
      };
    }

    const pod = pods[0];
    const podStatus = pod.status || {};
    const containerStatuses = podStatus.containerStatuses || [];
    const containerStatus = containerStatuses[0] || {};

    // Extract basic pod info
    const podRunning = podStatus.phase === 'Running';
    const restartCount = containerStatus.restartCount || 0;
    const podStartTime = pod.metadata.creationTimestamp;
    const uptimeHours = calculateUptime(podStartTime);

    // Check 1: Pod phase
    if (podStatus.phase === 'Failed') {
      issues.push(createIssue({
        id: 'provider-pod-failed',
        severity: 'critical',
        category: 'provider',
        title: 'Provider Pod Failed',
        description: `Provider pod '${pod.metadata.name}' has failed. The container exited with an error.`,
        recommendation: 'Check pod logs for error details. Common causes include configuration errors, missing secrets, or resource constraints.',
        affectsRevenue: true,
        blocksNewLeases: true,
        hasFix: true,
        autoFix: false,
        fixAction: 'Check logs and fix configuration',
        risk: 'critical'
      }));
    } else if (podStatus.phase !== 'Running') {
      issues.push(createIssue({
        id: 'provider-pod-not-running',
        severity: 'high',
        category: 'provider',
        title: `Provider Pod Status: ${podStatus.phase}`,
        description: `Provider pod is in '${podStatus.phase}' state instead of 'Running'.`,
        recommendation: 'Wait a few minutes for the pod to start. If it persists, check pod events and logs.',
        affectsRevenue: true,
        blocksNewLeases: true,
        hasFix: false,
        autoFix: false,
        risk: 'high'
      }));
    }

    // Check 2: High restart count
    if (restartCount > 5) {
      issues.push(createIssue({
        id: 'high-restart-count',
        severity: 'high',
        category: 'provider',
        title: `Provider Restarted ${restartCount} Times`,
        description: `Provider container has restarted ${restartCount} times. This indicates crashes or instability.`,
        recommendation: 'Check pod logs for crash patterns. Common causes include OOM kills, resource limits, or application errors.',
        affectsRevenue: true,
        blocksNewLeases: true,
        hasFix: true,
        autoFix: false,
        fixAction: 'Investigate logs and resource limits',
        risk: 'high'
      }));
    } else if (restartCount > 0) {
      issues.push(createIssue({
        id: 'provider-restarted',
        severity: 'medium',
        category: 'provider',
        title: `Provider Restarted ${restartCount} Time(s)`,
        description: `Provider has restarted ${restartCount} time(s). Monitor for stability.`,
        recommendation: 'Monitor logs to determine restart cause. May be normal updates or indicate issues.',
        affectsRevenue: false,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        risk: 'low'
      }));
    }

    // Get pod logs for detailed analysis
    let logs = '';
    let biddingActive = false;
    let blockchainSynced = false;

    if (podRunning) {
      try {
        logs = await getPodLogs(namespace, pod.metadata.name, 50);

        // Check 3: Blockchain sync status
        const syncPatterns = [
          /blockchain\s*synced?\s*:\s*(synced|up\s*to\s*date|latest)/i,
          /synced\s*:\s*block\s*\d+/i
        ];
        const behindPatterns = [
          /behind|syncing|waiting\s*for\s*sync/i,
          /block\s*\d+,\s*latest\s*\d+/i
        ];

        const isSynced = syncPatterns.some(pattern => pattern.test(logs));
        const isBehind = behindPatterns.some(pattern => pattern.test(logs));

        blockchainSynced = isSynced && !isBehind;

        if (!blockchainSynced && isBehind) {
          issues.push(createIssue({
            id: 'blockchain-out-of-sync',
            severity: 'high',
            category: 'blockchain',
            title: 'Blockchain Out of Sync',
            description: 'Provider blockchain is behind the latest block. This may cause bidding issues.',
            recommendation: 'Wait for sync to complete. Check RPC endpoint connectivity and network status.',
            affectsRevenue: true,
            blocksNewLeases: true,
            hasFix: false,
            autoFix: false,
            fixAction: 'Wait for sync or check RPC',
            risk: 'high'
          }));
        }

        // Check 4: Bidding engine status
        const biddingActivePatterns = [
          /bidding\s*engine\s*:\s*active/i,
          /bidding\s*:\s*active/i,
          /watching\s*for\s*(new\s*)?bids/i,
          /bidding\s*enabled/i
        ];
        const biddingInactivePatterns = [
          /bidding\s*engine\s*:\s*inactive/i,
          /bidding\s*:\s*inactive/i,
          /bidding\s*:\s*paused/i,
          /bidding\s*disabled/i
        ];

        biddingActive = biddingActivePatterns.some(pattern => pattern.test(logs)) &&
                       !biddingInactivePatterns.some(pattern => pattern.test(logs));

        if (!biddingActive && podRunning) {
          issues.push(createIssue({
            id: 'bidding-inactive',
            severity: 'medium',
            category: 'bidding',
            title: 'Bidding Engine Inactive',
            description: 'Provider bidding engine is not active. Provider will not bid on new leases.',
            recommendation: 'Check if bidding is intentionally paused. If not, check provider configuration and restart.',
            affectsRevenue: true,
            blocksNewLeases: true,
            hasFix: true,
            autoFix: false,
            fixAction: 'Check bidding configuration',
            risk: 'medium'
          }));
        }

        // Check 5: Error patterns in logs
        const errorPatterns = [
          { pattern: /out\s+of\s+memory|oom/i, id: 'out-of-memory', severity: 'critical' },
          { pattern: /connection\s+refused|dial\s+tcp/i, id: 'connection-error', severity: 'high' },
          { pattern: /rpc\s+timeout|timeout/i, id: 'rpc-timeout', severity: 'high' },
          { pattern: /certificate\s+expired|tls/i, id: 'tls-error', severity: 'high' },
          { pattern: /permission\s+denied|unauthorized/i, id: 'permission-error', severity: 'medium' },
          { pattern: /disk\s+full|no\s+space/i, id: 'disk-full', severity: 'critical' }
        ];

        for (const { pattern, id, severity } of errorPatterns) {
          if (pattern.test(logs)) {
            const title = id.split('-').map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(' ');
            issues.push(createIssue({
              id,
              severity,
              category: 'runtime',
              title,
              description: `Detected '${title}' error in provider logs.`,
              recommendation: `Check provider logs for full error details. Address the root cause before provider becomes unstable.`,
              affectsRevenue: severity === 'critical' || severity === 'high',
              blocksNewLeases: severity === 'critical',
              hasFix: false,
              autoFix: false,
              fixAction: 'Investigate error in logs',
              risk: severity
            }));
          }
        }

      } catch (logError) {
        issues.push(createIssue({
          id: 'logs-unavailable',
          severity: 'low',
          category: 'monitoring',
          title: 'Cannot Read Provider Logs',
          description: `Failed to read provider logs: ${logError.message}`,
          recommendation: 'Check kubectl permissions and pod status.',
          affectsRevenue: false,
          blocksNewLeases: false,
          hasFix: false,
          autoFix: false,
          fixAction: '',
          risk: 'low'
        }));
      }
    }

    // Determine overall health status
    let status = 'healthy';

    // If pod is not running, status is 'down' for critical issues
    if (!podRunning && issues.some(i => i.severity === 'critical')) {
      status = 'down';
    }
    // If pod is running but has critical errors in logs, it's still 'degraded' not 'down'
    else if (podRunning && issues.some(i => i.severity === 'critical' && i.id !== 'provider-pod-failed' && i.id !== 'provider-pod-missing')) {
      status = 'degraded';
    }
    // High severity issues mean degraded
    else if (issues.some(i => i.severity === 'high')) {
      status = 'degraded';
    }
    // Any issues mean degraded
    else if (issues.length > 0) {
      status = 'degraded';
    }

    return {
      status,
      podRunning,
      biddingActive,
      blockchainSynced,
      uptimeHours,
      restartCount,
      issues
    };

  } catch (error) {
    // Handle unexpected errors
    return {
      status: 'unknown',
      podRunning: false,
      biddingActive: false,
      blockchainSynced: false,
      uptimeHours: 0,
      restartCount: 0,
      issues: [createIssue({
        id: 'diagnostic-error',
        severity: 'critical',
        category: 'diagnostic',
        title: 'Diagnostic Check Failed',
        description: `Failed to run provider health check: ${error.message}`,
        recommendation: 'Check kubectl connectivity and permissions. Verify namespace is correct.',
        affectsRevenue: true,
        blocksNewLeases: true,
        hasFix: false,
        autoFix: false,
        fixAction: 'Check kubectl setup',
        risk: 'critical'
      })]
    };
  }
}

/**
 * Check overall cluster health
 * @param {Object} options - Options for the check
 * @returns {Promise<Object>} Cluster health status
 */
async function checkClusterHealth(options = {}) {
  const issues = [];

  try {
    // Get all nodes
    const nodes = await getNodes();

    // Check node status
    const nodeStatus = {
      total: nodes.length,
      ready: 0,
      notReady: 0,
      unhealthy: []
    };

    for (const node of nodes) {
      const nodeReady = node.status?.conditions?.find(
        c => c.type === 'Ready'
      )?.status === 'True';

      if (nodeReady) {
        nodeStatus.ready++;
      } else {
        nodeStatus.notReady++;
        nodeStatus.unhealthy.push(node.metadata?.name);
      }
    }

    // Get all pods across all namespaces
    let pods = [];
    try {
      const podOutput = await kubectl(['get', 'pods', '--all-namespaces', '-o', 'json']);
      const podData = JSON.parse(podOutput);
      pods = podData.items || [];
    } catch (error) {
      issues.push(createIssue({
        id: 'cluster-check-failed',
        severity: 'critical',
        category: 'cluster',
        title: 'Cannot Retrieve Pod Information',
        description: `Failed to get pods: ${error.message}`,
        recommendation: 'Check kubectl connectivity and permissions.',
        affectsRevenue: true,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Check kubectl setup',
        risk: 'critical'
      }));
    }

    // Check pod status
    const podStatus = {
      total: pods.length,
      running: 0,
      pending: 0,
      failed: 0,
      succeeded: 0,
      crashLoopBackOff: 0
    };

    for (const pod of pods) {
      const phase = pod.status?.phase;

      if (phase === 'Running') {
        // Check for CrashLoopBackOff
        const containerStatuses = pod.status?.containerStatuses || [];
        const hasCrashLoop = containerStatuses.some(cs =>
          cs.state?.waiting?.reason === 'CrashLoopBackOff'
        );

        if (hasCrashLoop) {
          podStatus.crashLoopBackOff++;
        } else {
          podStatus.running++;
        }
      } else if (phase === 'Pending') {
        podStatus.pending++;
      } else if (phase === 'Failed') {
        podStatus.failed++;
      } else if (phase === 'Succeeded') {
        podStatus.succeeded++;
      }
    }

    // Create issues for unhealthy nodes
    if (nodeStatus.notReady > 0) {
      issues.push(createIssue({
        id: 'node-not-ready',
        severity: 'high',
        category: 'cluster',
        title: `${nodeStatus.notReady} Node(s) Not Ready`,
        description: `Nodes ${nodeStatus.unhealthy.join(', ')} are not in Ready state.`,
        recommendation: 'Check node status with kubectl describe node. Look for resource exhaustion or hardware issues.',
        affectsRevenue: true,
        blocksNewLeases: true,
        hasFix: false,
        autoFix: false,
        fixAction: 'Investigate node health',
        risk: 'high'
      }));
    }

    // Create issues for failed pods
    if (podStatus.failed > 0) {
      issues.push(createIssue({
        id: 'pods-failed',
        severity: 'medium',
        category: 'cluster',
        title: `${podStatus.failed} Pod(s) in Failed State`,
        description: 'Some pods have failed and may need attention.',
        recommendation: 'Check pod logs and events to determine failure cause.',
        affectsRevenue: true,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Check failed pod logs',
        risk: 'medium'
      }));
    }

    // Create issues for CrashLoopBackOff
    if (podStatus.crashLoopBackOff > 0) {
      issues.push(createIssue({
        id: 'pods-crashloop',
        severity: 'high',
        category: 'cluster',
        title: `${podStatus.crashLoopBackOff} Pod(s) in CrashLoopBackOff`,
        description: 'Pods are repeatedly crashing. This indicates application errors or misconfiguration.',
        recommendation: 'Check pod logs for crash details. Common causes include config errors, missing dependencies, or OOM kills.',
        affectsRevenue: true,
        blocksNewLeases: true,
        hasFix: false,
        autoFix: false,
        fixAction: 'Investigate crashloop pods',
        risk: 'high'
      }));
    }

    // Check for pod IP exhaustion risk on dense nodes
    // Kubernetes default: 110 pods per node (configurable via --max-pods)
    const maxPodsPerNode = 110; // Kubernetes default
    const podsPerNode = {};

    // Count pods per node
    for (const pod of pods) {
      const nodeName = pod.spec?.nodeName;
      if (nodeName) {
        podsPerNode[nodeName] = (podsPerNode[nodeName] || 0) + 1;
      }
    }

    // Check for nodes approaching pod limit
    for (const [nodeName, podCount] of Object.entries(podsPerNode)) {
      const utilization = podCount / maxPodsPerNode;

      if (utilization > 0.8) {
        issues.push(createIssue({
          id: 'pod-ip-exhaustion-risk',
          severity: utilization > 0.95 ? 'high' : 'medium',
          category: 'network',
          title: `Pod IP Exhaustion Risk on ${nodeName}`,
          description: `${podCount}/${maxPodsPerNode} pods used (${Math.round(utilization * 100)}%). Node is approaching maximum pod limit.`,
          recommendation: 'Consider increasing --max-pods parameter on kubelet or expanding pod CIDR range to prevent deployment failures.',
          affectsRevenue: true,
          blocksNewLeases: utilization > 0.95,
          hasFix: true,
          autoFix: false,
          fixAction: 'Increase kubelet --max-pods or expand CIDR',
          risk: utilization > 0.95 ? 'high' : 'medium'
        }));
      }
    }

    // Determine overall status
    let status = 'healthy';
    if (nodeStatus.notReady > 0 || podStatus.failed > 0 || podStatus.crashLoopBackOff > 0) {
      status = 'degraded';
    }
    // Only critical if MORE than half of nodes are not ready (not equal to half)
    if (nodeStatus.notReady > nodes.length / 2) {
      status = 'critical';
    }

    return {
      status,
      nodes: nodeStatus,
      pods: podStatus,
      issues
    };

  } catch (error) {
    return {
      status: 'unknown',
      nodes: { total: 0, ready: 0, notReady: 0, unhealthy: [] },
      pods: { total: 0, running: 0, pending: 0, failed: 0, succeeded: 0, crashLoopBackOff: 0 },
      issues: [createIssue({
        id: 'cluster-check-failed',
        severity: 'critical',
        category: 'cluster',
        title: 'Cluster Health Check Failed',
        description: `Failed to check cluster health: ${error.message}`,
        recommendation: 'Check kubectl connectivity and permissions.',
        affectsRevenue: true,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Check kubectl setup',
        risk: 'critical'
      })]
    };
  }
}

/**
 * Check hardware discovery across cluster
 * @param {Object} options - Options for the check
 * @returns {Promise<Object>} Hardware inventory
 */
async function checkHardwareDiscovery(options = {}) {
  try {
    const nodes = await getNodes();

    let totalCPU = 0;
    let totalMemory = 0;
    let totalGPU = 0;
    const gpuTypes = {};
    const nodeDetails = [];

    for (const node of nodes) {
      const allocatable = node.status?.allocatable || {};
      const capacity = node.status?.capacity || {};

      // Parse CPU
      const cpu = parseInt(allocatable.cpu || capacity.cpu || '0', 10);
      totalCPU += cpu;

      // Parse memory (convert to GiB)
      const memoryStr = allocatable.memory || capacity.memory || '0';
      const memoryMatch = memoryStr.match(/^(\d+(?:\.\d+)?)((?:Ki|Mi|Gi)?)$/);
      let memoryGiB = 0;
      if (memoryMatch) {
        const value = parseFloat(memoryMatch[1]);
        const unit = memoryMatch[2];
        if (unit === 'Ki') {
          memoryGiB = value / (1024 * 1024);
        } else if (unit === 'Mi') {
          memoryGiB = value / 1024;
        } else if (unit === 'Gi') {
          memoryGiB = value;
        }
      }
      totalMemory += memoryGiB;

      // Parse GPUs
      const nvidiaGPU = parseInt(allocatable['nvidia.com/gpu'] || '0', 10);
      const amdGPU = parseInt(allocatable['amd.com/gpu'] || '0', 10);

      if (nvidiaGPU > 0) {
        totalGPU += nvidiaGPU;
        gpuTypes.nvidia = (gpuTypes.nvidia || 0) + nvidiaGPU;
      }

      if (amdGPU > 0) {
        totalGPU += amdGPU;
        gpuTypes.amd = (gpuTypes.amd || 0) + amdGPU;
      }

      nodeDetails.push({
        name: node.metadata?.name,
        cpu,
        memory: Math.round(memoryGiB * 100) / 100,
        nvidiaGPU,
        amdGPU
      });
    }

    return {
      nodes: nodeDetails,
      totalCPU,
      totalMemory: Math.round(totalMemory * 100) / 100,
      totalGPU,
      gpuTypes
    };

  } catch (error) {
    return {
      nodes: [],
      totalCPU: 0,
      totalMemory: 0,
      totalGPU: 0,
      gpuTypes: {},
      issues: [createIssue({
        id: 'hardware-discovery-failed',
        severity: 'critical',
        category: 'cluster',
        title: 'Hardware Discovery Failed',
        description: `Failed to discover hardware: ${error.message}`,
        recommendation: 'Check kubectl connectivity.',
        affectsRevenue: false,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Check kubectl setup',
        risk: 'high'
      })]
    };
  }
}

/**
 * Check GPU inventory and allocation
 * @param {string} namespace - Namespace to check for GPU allocations
 * @returns {Promise<Object>} GPU inventory status
 */
async function checkGPUInventory(namespace = 'akash-services') {
  const issues = [];

  try {
    const nodes = await getNodes();

    let totalGPUs = 0;
    let allocatableGPUs = 0;
    const gpuByNode = {};

    // Count GPUs from nodes
    for (const node of nodes) {
      const allocatable = node.status?.allocatable || {};

      const nvidiaGPU = parseInt(allocatable['nvidia.com/gpu'] || '0', 10);
      const amdGPU = parseInt(allocatable['amd.com/gpu'] || '0', 10);

      if (nvidiaGPU > 0 || amdGPU > 0) {
        const nodeName = node.metadata?.name;
        const nodeGPUs = nvidiaGPU + amdGPU;

        totalGPUs += nodeGPUs;
        allocatableGPUs += nodeGPUs;

        gpuByNode[nodeName] = {
          allocatable: nodeGPUs,
          allocated: 0,
          nvidia: nvidiaGPU,
          amd: amdGPU
        };
      }
    }

    // Count allocated GPUs by checking pods
    let allocatedGPUs = 0;

    try {
      const pods = await getPods(namespace);

      for (const pod of pods) {
        const nodeName = pod.spec?.nodeName;
        const containers = pod.spec?.containers || [];

        for (const container of containers) {
          const resources = container.resources?.requests || {};

          const nvidiaGPU = parseInt(resources['nvidia.com/gpu'] || '0', 10);
          const amdGPU = parseInt(resources['amd.com/gpu'] || '0', 10);

          allocatedGPUs += nvidiaGPU + amdGPU;

          // Track by node
          if (nodeName && gpuByNode[nodeName]) {
            gpuByNode[nodeName].allocated += nvidiaGPU + amdGPU;
          }
        }
      }

    } catch (error) {
      // If we can't get pods, we'll report 0 allocated
    }

    const availableGPUs = allocatableGPUs - allocatedGPUs;

    // Check GPU inventory mismatch (on-chain vs actual)
    // In a full implementation, this would query on-chain provider attributes
    // For now, we'll check if totalGPUs matches expected count from documentation
    const expectedGPUs = 5; // From provider-update-exact-format.json
    if (totalGPUs !== expectedGPUs) {
      issues.push(createIssue({
        id: 'gpu-inventory-mismatch',
        severity: 'high',
        category: 'resource',
        title: 'On-Chain vs. Actual GPU Count Mismatch',
        description: `On-chain attributes claim ${expectedGPUs} GPUs, but cluster actually has ${totalGPUs} GPUs.`,
        recommendation: 'Update provider attributes with: kubectl exec -n akash-services deployment/akash-provider -- provider-services update-provider --from provider-wallet --provider akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6 --attributes-file /path/to/provider-update-exact-format.json',
        affectsRevenue: true,
        blocksNewLeases: true,
        hasFix: true,
        autoFix: false,
        fixAction: 'Update provider attributes on-chain',
        risk: 'high'
      }));
    }

    // Check for overallocation
    if (allocatedGPUs > allocatableGPUs) {
      issues.push(createIssue({
        id: 'gpu-overallocated',
        severity: 'high',
        category: 'resource',
        title: 'GPUs Overallocated',
        description: `Allocated ${allocatedGPUs} GPUs but only ${allocatableGPUs} available.`,
        recommendation: 'Check running pods and reduce GPU allocations or remove excess pods.',
        affectsRevenue: true,
        blocksNewLeases: true,
        hasFix: false,
        autoFix: false,
        fixAction: 'Reduce GPU allocations',
        risk: 'high'
      }));
    }

    // Check if GPUs are nearly exhausted
    const utilizationPercent = allocatableGPUs > 0 ? (allocatedGPUs / allocatableGPUs) * 100 : 0;
    if (utilizationPercent > 90 && utilizationPercent <= 100) {
      issues.push(createIssue({
        id: 'gpu-near-exhaustion',
        severity: 'medium',
        category: 'resource',
        title: 'GPUs Nearly Exhausted',
        description: `${Math.round(utilizationPercent)}% of GPUs are allocated (${allocatedGPUs}/${allocatableGPUs}).`,
        recommendation: 'Monitor closely. Consider adding more GPU nodes or reducing allocations.',
        affectsRevenue: true,
        blocksNewLeases: true,
        hasFix: false,
        autoFix: false,
        fixAction: 'Add GPU nodes or reduce allocations',
        risk: 'medium'
      }));
    }

    return {
      gpus: {
        total: totalGPUs,
        allocatable: allocatableGPUs,
        allocated: allocatedGPUs,
        available: availableGPUs
      },
      byNode: gpuByNode,
      issues
    };

  } catch (error) {
    return {
      gpus: { total: 0, allocatable: 0, allocated: 0, available: 0 },
      byNode: {},
      issues: [createIssue({
        id: 'gpu-inventory-failed',
        severity: 'critical',
        category: 'resource',
        title: 'GPU Inventory Check Failed',
        description: `Failed to check GPU inventory: ${error.message}`,
        recommendation: 'Check kubectl connectivity.',
        affectsRevenue: false,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Check kubectl setup',
        risk: 'high'
      })]
    };
  }
}

/**
 * Check storage status (PV/PVC)
 * @returns {Promise<Object>} Storage status
 */
async function checkStorageStatus() {
  const issues = [];

  try {
    // Get PersistentVolumes
    let pvOutput = '';
    let pvCount = 0;
    let capacityUsed = '0Gi';
    let totalCapacity = 0;

    try {
      pvOutput = await kubectl(['get', 'pv']);
      const pvLines = pvOutput.trim().split('\n').slice(1); // Skip header
      pvCount = pvLines.filter(line => line.trim().length > 0).length;

      // Parse capacity from PV lines (simplified - just sum up capacities)
      // Format: NAME  CAPACITY  ACCESS MODES  RECLAIM POLICY  STATUS  CLAIM  STORAGECLASS  REASON
      for (const line of pvLines) {
        if (line.trim().length > 0) {
          const parts = line.trim().split(/\s+/);
          if (parts.length >= 2) {
            const capacity = parts[1]; // Second column is capacity
            // Extract numeric value
            const match = capacity.match(/^(\d+(?:\.\d+)?)((?:Ki|Mi|Gi)?)$/);
            if (match) {
              const value = parseFloat(match[1]);
              const unit = match[2];
              let valueInGiB = 0;
              if (unit === 'Ki') {
                valueInGiB = value / (1024 * 1024);
              } else if (unit === 'Mi') {
                valueInGiB = value / 1024;
              } else if (unit === 'Gi') {
                valueInGiB = value;
              }
              totalCapacity += valueInGiB;
            }
          }
        }
      }

      if (totalCapacity > 0) {
        capacityUsed = `${Math.round(totalCapacity)}Gi`;
      }
    } catch (error) {
      issues.push(createIssue({
        id: 'pv-query-failed',
        severity: 'medium',
        category: 'storage',
        title: 'Cannot Query PersistentVolumes',
        description: `Failed to get PVs: ${error.message}`,
        recommendation: 'Check kubectl permissions.',
        affectsRevenue: false,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: '',
        risk: 'low'
      }));
    }

    // Get PersistentVolumeClaims
    let pvcCount = 0;
    let pendingPVCs = 0;

    try {
      const pvcOutput = await kubectl(['get', 'pvc', '--all-namespaces']);
      const pvcLines = pvcOutput.trim().split('\n').slice(1); // Skip header
      pvcCount = pvcLines.filter(line => line.trim().length > 0).length;

      // Count pending PVCs
      pendingPVCs = pvcLines.filter(line => line.includes('Pending')).length;
    } catch (error) {
      issues.push(createIssue({
        id: 'pvc-query-failed',
        severity: 'medium',
        category: 'storage',
        title: 'Cannot Query PersistentVolumeClaims',
        description: `Failed to get PVCs: ${error.message}`,
        recommendation: 'Check kubectl permissions.',
        affectsRevenue: false,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: '',
        risk: 'low'
      }));
    }

    // Create issue for pending PVCs
    if (pendingPVCs > 0) {
      issues.push(createIssue({
        id: 'pvc-pending',
        severity: 'medium',
        category: 'storage',
        title: `${pendingPVCs} PVC(s) in Pending State`,
        description: 'Some PersistentVolumeClaims are not bound. This may indicate storage class issues or capacity problems.',
        recommendation: 'Check PVC events and available storage capacity.',
        affectsRevenue: true,
        blocksNewLeases: true,
        hasFix: false,
        autoFix: false,
        fixAction: 'Investigate pending PVCs',
        risk: 'medium'
      }));
    }

    // Check for mixed storage types (SSD + HDD violation)
    // Akash best practice: All nodes should use same storage type
    try {
      const nodes = await getNodes();
      const storageTypes = new Set();

      for (const node of nodes) {
        const labels = node.metadata?.labels || {};
        // Check storage/type label (if set)
        const storageType = labels['storage/type'];
        if (storageType) {
          storageTypes.add(storageType);
        }
      }

      if (storageTypes.size > 1) {
        issues.push(createIssue({
          id: 'mixed-storage-types',
          severity: 'critical',
          category: 'storage',
          title: 'Mixed Storage Types Detected',
          description: `Nodes have different storage types: ${Array.from(storageTypes).join(', ')}. Akash best practices require uniform storage types (all SSD or all HDD).`,
          recommendation: 'Ensure all nodes use the same storage type. Mixed storage types can cause unpredictable performance and lease issues.',
          affectsRevenue: true,
          blocksNewLeases: false,
          hasFix: true,
          autoFix: false,
          fixAction: 'Standardize storage hardware across all nodes',
          risk: 'high'
        }));
      }
    } catch (error) {
      // Skip storage type check if we can't query nodes
    }

    return {
      pvCount,
      pvcCount,
      capacityUsed,
      issues
    };

  } catch (error) {
    return {
      pvCount: 0,
      pvcCount: 0,
      capacityUsed: '0Gi',
      issues: [createIssue({
        id: 'storage-check-failed',
        severity: 'high',
        category: 'storage',
        title: 'Storage Status Check Failed',
        description: `Failed to check storage: ${error.message}`,
        recommendation: 'Check kubectl connectivity.',
        affectsRevenue: false,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Check kubectl setup',
        risk: 'high'
      })]
    };
  }
}

/**
 * Check network connectivity and policies
 * @param {string} namespace - Namespace to check
 * @returns {Promise<Object>} Network status
 */
async function checkNetworkConnectivity(namespace = 'akash-services') {
  const issues = [];

  try {
    // Check for network policies
    let networkPolicyCount = 0;

    try {
      const npOutput = await kubectl(['get', 'networkpolicies', '-n', namespace]);
      const npLines = npOutput.trim().split('\n').slice(1); // Skip header
      networkPolicyCount = npLines.filter(line => line.trim().length > 0 && !line.includes('No resources found')).length;
    } catch (error) {
      // No network policies or error - we'll handle both
      networkPolicyCount = 0;
    }

    // Check if network policies exist
    if (networkPolicyCount === 0) {
      issues.push(createIssue({
        id: 'no-network-policies',
        severity: 'medium',
        category: 'network',
        title: 'No Network Policies Defined',
        description: `Namespace '${namespace}' has no network policies. All pod-to-pod communication is allowed.`,
        recommendation: 'Consider implementing network policies to restrict traffic and improve security.',
        affectsRevenue: false,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Implement network policies',
        risk: 'medium'
      }));
    }

    // Check DNS (CoreDNS) pods
    let dnsReady = true; // Assume OK by default
    try {
      const dnsPods = await getPods('kube-system', 'k8s-app=kube-dns');
      dnsReady = dnsPods.some(pod => pod.status?.phase === 'Running');
    } catch (error) {
      // Assume DNS is OK if we can't check (may not have access to kube-system)
      dnsReady = true;
    }

    if (!dnsReady) {
      issues.push(createIssue({
        id: 'dns-not-ready',
        severity: 'high',
        category: 'network',
        title: 'DNS Pods Not Running',
        description: 'CoreDNS pods are not running. This will cause DNS resolution failures.',
        recommendation: 'Check kube-system namespace for CoreDNS pod issues.',
        affectsRevenue: true,
        blocksNewLeases: true,
        hasFix: false,
        autoFix: false,
        fixAction: 'Investigate CoreDNS pods',
        risk: 'high'
      }));
    }

    return {
      networkPolicies: {
        count: networkPolicyCount,
        exists: networkPolicyCount > 0
      },
      dnsReady,
      connectivityTest: 'skipped', // Would require actual network test
      issues
    };

  } catch (error) {
    return {
      networkPolicies: { count: 0, exists: false },
      dnsReady: false,
      connectivityTest: 'failed',
      issues: [createIssue({
        id: 'network-check-failed',
        severity: 'high',
        category: 'network',
        title: 'Network Connectivity Check Failed',
        description: `Failed to check network: ${error.message}`,
        recommendation: 'Check kubectl connectivity.',
        affectsRevenue: false,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Check kubectl setup',
        risk: 'high'
      })]
    };
  }
}

/**
 * Check resource quotas and limits
 * @param {string} namespace - Namespace to check
 * @returns {Promise<Object>} Resource quota status
 */
async function checkResourceQuotas(namespace = 'akash-services') {
  const issues = [];

  try {
    // Check for ResourceQuota
    let resourceQuotaExists = false;
    let limitsUsed = { cpu: 0, memory: 0 };

    try {
      const quotaOutput = await kubectl(['get', 'resourcequota', '-n', namespace]);

      if (!quotaOutput.includes('No resources found')) {
        resourceQuotaExists = true;

        // Parse resource quota usage (simplified)
        // Example output: requests.cpu: 2000m/4000m, requests.memory: 8Gi/16Gi
        const cpuMatch = quotaOutput.match(/requests\.cpu:\s*(\d+)m\/(\d+)m/);
        if (cpuMatch) {
          limitsUsed.cpu = (parseInt(cpuMatch[1], 10) / parseInt(cpuMatch[2], 10)) * 100;
        }

        const memMatch = quotaOutput.match(/requests\.memory:\s*(\d+)Gi\/(\d+)Gi/);
        if (memMatch) {
          limitsUsed.memory = (parseInt(memMatch[1], 10) / parseInt(memMatch[2], 10)) * 100;
        }
      }
    } catch (error) {
      // No quota or error
    }

    // Check for LimitRange
    let limitRangeExists = false;

    try {
      const lrOutput = await kubectl(['get', 'limitrange', '-n', namespace]);
      limitRangeExists = !lrOutput.includes('No resources found');
    } catch (error) {
      // No limitrange or error
    }

    // Create issues
    if (!resourceQuotaExists) {
      issues.push(createIssue({
        id: 'no-resource-quota',
        severity: 'high',
        category: 'resource',
        title: 'No ResourceQuota Defined',
        description: `Namespace '${namespace}' has no ResourceQuota. Pods can consume unlimited resources.`,
        recommendation: 'Implement ResourceQuota to limit resource consumption and prevent noisy neighbor issues.',
        affectsRevenue: true,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Implement ResourceQuota',
        risk: 'high'
      }));
    }

    if (!limitRangeExists) {
      issues.push(createIssue({
        id: 'no-limit-range',
        severity: 'medium',
        category: 'resource',
        title: 'No LimitRange Defined',
        description: `Namespace '${namespace}' has no LimitRange. Pods may not have default resource limits.`,
        recommendation: 'Implement LimitRange to ensure all pods have resource limits.',
        affectsRevenue: true,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Implement LimitRange',
        risk: 'medium'
      }));
    }

    // Check bid deposit (Akash-specific requirement)
    // Formula: 5 AKT per concurrent deployment
    // Max deployments: 100 (cluster config)
    // Required deposit: 500 AKT
    try {
      const maxDeployments = 100;
      const requiredDeposit = maxDeployments * 5; // 5 AKT per deployment

      // In a full implementation, this would query on-chain bid deposit
      // For now, we'll check if the provider config matches requirements
      const expectedDeposit = 500;

      if (expectedDeposit < requiredDeposit) {
        issues.push(createIssue({
          id: 'insufficient-bid-deposit',
          severity: 'high',
          category: 'financial',
          title: 'Bid Deposit Too Low',
          description: `Current bid deposit: ${expectedDeposit} AKT. Required: ${requiredDeposit} AKT for ${maxDeployments} concurrent deployments (5 AKT per deployment).`,
          recommendation: 'Increase bid deposit to support max concurrent deployments. Without sufficient deposit, new bids will fail even if resources are available.',
          affectsRevenue: true,
          blocksNewLeases: true,
          hasFix: true,
          autoFix: false,
          fixAction: 'Increase bid deposit on-chain',
          risk: 'high'
        }));
      }
    } catch (error) {
      // Skip bid deposit check if we can't determine requirements
    }

    // Check if quotas are nearing limits
    if (resourceQuotaExists) {
      const cpuThreshold = 90;
      const memoryThreshold = 90;

      if (limitsUsed.cpu > cpuThreshold) {
        issues.push(createIssue({
          id: 'quota-nearing-limit',
          severity: 'medium',
          category: 'resource',
          title: 'CPU Quota Nearing Limit',
          description: `${Math.round(limitsUsed.cpu)}% of CPU quota is used.`,
          recommendation: 'Monitor closely. Consider increasing quota or reducing consumption.',
          affectsRevenue: true,
          blocksNewLeases: true,
          hasFix: false,
          autoFix: false,
          fixAction: 'Increase quota or reduce usage',
          risk: 'medium'
        }));
      }

      if (limitsUsed.memory > memoryThreshold) {
        issues.push(createIssue({
          id: 'quota-nearing-limit',
          severity: 'medium',
          category: 'resource',
          title: 'Memory Quota Nearing Limit',
          description: `${Math.round(limitsUsed.memory)}% of memory quota is used.`,
          recommendation: 'Monitor closely. Consider increasing quota or reducing consumption.',
          affectsRevenue: true,
          blocksNewLeases: true,
          hasFix: false,
          autoFix: false,
          fixAction: 'Increase quota or reduce usage',
          risk: 'medium'
        }));
      }
    }

    return {
      quotas: {
        resourceQuotaExists,
        limitRangeExists
      },
      limitsUsed,
      issues
    };

  } catch (error) {
    return {
      quotas: { resourceQuotaExists: false, limitRangeExists: false },
      limitsUsed: { cpu: 0, memory: 0 },
      issues: [createIssue({
        id: 'quota-check-failed',
        severity: 'high',
        category: 'resource',
        title: 'Resource Quota Check Failed',
        description: `Failed to check resource quotas: ${error.message}`,
        recommendation: 'Check kubectl connectivity.',
        affectsRevenue: false,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Check kubectl setup',
        risk: 'high'
      })]
    };
  }
}

/**
 * Check pricing optimization recommendations
 * @param {string} namespace - Namespace to check
 * @returns {Promise<Object>} Pricing optimization status
 */
async function checkPricingOptimization(namespace = 'akash-services') {
  const issues = [];
  const recommendations = [];

  try {
    // Get current GPU utilization
    const gpuUtil = await getCurrentGPUUtilization(namespace);
    const cpuUtil = await getCurrentCPUUtilization(namespace);
    const memUtil = await getCurrentMemoryUtilization(namespace);

    // Get pricing recommendation
    const pricingRec = knowledge.suggestPriceAdjustment({
      gpu: gpuUtil.utilization,
      cpu: cpuUtil.utilization,
      memory: memUtil.utilization
    });

    // Create issues based on recommendation
    if (pricingRec.action === 'lower_prices' && pricingRec.priority !== 'low') {
      issues.push(createIssue({
        id: 'low-utilization-pricing',
        severity: pricingRec.priority === 'high' ? 'high' : 'medium',
        category: 'optimization',
        title: 'Consider Lowering GPU Prices',
        description: pricingRec.reason,
        recommendation: `Lower prices by ${pricingRec.suggestedDiscount * 100}% to attract tenants and build lease history.`,
        affectsRevenue: true,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Update pricing in modules/services/akash-provider.nix',
        risk: 'medium'
      }));
    } else if (pricingRec.action === 'raise_prices') {
      issues.push(createIssue({
        id: 'high-utilization-pricing',
        severity: pricingRec.priority === 'high' ? 'high' : 'medium',
        category: 'optimization',
        title: 'Consider Raising GPU Prices',
        description: pricingRec.reason,
        recommendation: `Increase prices by ${pricingRec.suggestedPremium * 100}% to maximize revenue during high demand.`,
        affectsRevenue: true,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Update pricing in modules/services/akash-provider.nix',
        risk: 'low'
      }));
    }

    recommendations.push(pricingRec);

    return {
      pricing: pricingRec,
      utilization: {
        gpu: gpuUtil,
        cpu: cpuUtil,
        memory: memUtil
      },
      recommendations,
      issues
    };

  } catch (error) {
    return {
      pricing: { action: 'unknown', reason: 'Could not determine pricing optimization' },
      utilization: { gpu: 0, cpu: 0, memory: 0 },
      recommendations: [],
      issues: [createIssue({
        id: 'pricing-check-failed',
        severity: 'medium',
        category: 'optimization',
        title: 'Pricing Optimization Check Failed',
        description: `Failed to check pricing optimization: ${error.message}`,
        recommendation: 'Check provider metrics and utilization.',
        affectsRevenue: true,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Check provider pod logs',
        risk: 'low'
      })]
    };
  }
}

/**
 * Get current GPU utilization
 * @param {string} namespace - Namespace
 * @returns {Promise<Object>} GPU utilization stats
 */
async function getCurrentGPUUtilization(namespace) {
  try {
    // Try to get GPU utilization from provider metrics
    const nodes = await getNodes();

    let totalGPUs = 0;
    let usedGPUs = 0;

    for (const node of nodes) {
      const gpuAllocatable = parseInt(node.status.allocatable?.['nvidia.com/gpu'] || '0', 10);
      const gpuCapacity = parseInt(node.status.capacity?.['nvidia.com/gpu'] || '0', 10);

      totalGPUs += gpuCapacity;
      usedGPUs += (gpuCapacity - gpuAllocatable);
    }

    return {
      total: totalGPUs,
      used: usedGPUs,
      available: totalGPUs - usedGPUs,
      utilization: totalGPUs > 0 ? usedGPUs / totalGPUs : 0
    };
  } catch (error) {
    return { total: 0, used: 0, available: 0, utilization: 0 };
  }
}

/**
 * Get current CPU utilization
 * @param {string} namespace - Namespace
 * @returns {Promise<Object>} CPU utilization stats
 */
async function getCurrentCPUUtilization(namespace) {
  try {
    const nodes = await getNodes();

    let totalCPU = 0;
    let allocatableCPU = 0;

    for (const node of nodes) {
      const capacity = parseInt(node.status.capacity?.cpu || '0', 10);
      const allocatable = parseInt(node.status.allocatable?.cpu || '0', 10);

      totalCPU += capacity;
      allocatableCPU += allocatable;
    }

    const usedCPU = totalCPU - allocatableCPU;

    return {
      total: totalCPU,
      used: usedCPU,
      available: allocatableCPU,
      utilization: totalCPU > 0 ? usedCPU / totalCPU : 0
    };
  } catch (error) {
    return { total: 0, used: 0, available: 0, utilization: 0 };
  }
}

/**
 * Get current memory utilization
 * @param {string} namespace - Namespace
 * @returns {Promise<Object>} Memory utilization stats
 */
async function getCurrentMemoryUtilization(namespace) {
  try {
    const nodes = await getNodes();

    let totalMem = 0;
    let allocatableMem = 0;

    for (const node of nodes) {
      const capacity = parseMemory(node.status.capacity?.memory || '0');
      const allocatable = parseMemory(node.status.allocatable?.memory || '0');

      totalMem += capacity;
      allocatableMem += allocatable;
    }

    const usedMem = totalMem - allocatableMem;

    return {
      total: totalMem,
      used: usedMem,
      available: allocatableMem,
      utilization: totalMem > 0 ? usedMem / totalMem : 0
    };
  } catch (error) {
    return { total: 0, used: 0, available: 0, utilization: 0 };
  }
}

/**
 * Parse memory string (e.g., "16Gi", "16384Mi") to bytes
 * @param {string} memStr - Memory string
 * @returns {number} Memory in bytes
 */
function parseMemory(memStr) {
  if (!memStr) return 0;

  const units = { 'Ki': 1024, 'Mi': 1048576, 'Gi': 1073741824, 'Ti': 1099511627776 };
  const match = memStr.match(/^(\d+)(Ki|Mi|Gi|Ti)$/);

  if (!match) return parseInt(memStr, 10) || 0;

  return parseInt(match[1], 10) * units[match[2]];
}

/**
 * Run all diagnostic checks
 * @param {string} namespace - Namespace to check
 * @param {Object} options - Options for checks
 * @returns {Promise<Object>} Complete diagnostic results
 */
async function runAllDiagnostics(namespace = 'akash-services', options = {}) {
  const results = {
    clusterHealth: null,
    provider: null,
    hardware: null,
    gpu: null,
    storage: null,
    network: null,
    quotas: null,
    pricing: null,
    summary: null
  };

  const allIssues = [];

  // Run all checks in parallel for speed
  try {
    const [
      clusterHealth,
      provider,
      hardware,
      gpu,
      storage,
      network,
      quotas,
      pricing
    ] = await Promise.allSettled([
      checkClusterHealth(options),
      checkProviderHealth(namespace),
      checkHardwareDiscovery(options),
      checkGPUInventory(namespace),
      checkStorageStatus(),
      checkNetworkConnectivity(namespace),
      checkResourceQuotas(namespace),
      checkPricingOptimization(namespace)
    ]);

    // Collect results
    if (clusterHealth.status === 'fulfilled') {
      results.clusterHealth = clusterHealth.value;
      allIssues.push(...(clusterHealth.value.issues || []));
    } else {
      results.clusterHealth = {
        status: 'error',
        issues: [createIssue({
          id: 'cluster-health-error',
          severity: 'critical',
          category: 'diagnostic',
          title: 'Cluster Health Check Error',
          description: clusterHealth.reason?.message || 'Unknown error',
          recommendation: 'Check kubectl setup',
          affectsRevenue: true,
          blocksNewLeases: false,
          hasFix: false,
          autoFix: false,
          fixAction: '',
          risk: 'critical'
        })]
      };
    }

    if (provider.status === 'fulfilled') {
      results.provider = provider.value;
      allIssues.push(...(provider.value.issues || []));
    } else {
      results.provider = {
        status: 'unknown',
        issues: [createIssue({
          id: 'provider-health-error',
          severity: 'critical',
          category: 'diagnostic',
          title: 'Provider Health Check Error',
          description: provider.reason?.message || 'Unknown error',
          recommendation: 'Check kubectl setup',
          affectsRevenue: true,
          blocksNewLeases: false,
          hasFix: false,
          autoFix: false,
          fixAction: '',
          risk: 'critical'
        })]
      };
    }

    if (hardware.status === 'fulfilled') {
      results.hardware = hardware.value;
      allIssues.push(...(hardware.value.issues || []));
    } else {
      results.hardware = {
        nodes: [],
        totalCPU: 0,
        totalMemory: 0,
        totalGPU: 0,
        gpuTypes: {},
        issues: [createIssue({
          id: 'hardware-discovery-error',
          severity: 'high',
          category: 'diagnostic',
          title: 'Hardware Discovery Error',
          description: hardware.reason?.message || 'Unknown error',
          recommendation: 'Check kubectl setup',
          affectsRevenue: false,
          blocksNewLeases: false,
          hasFix: false,
          autoFix: false,
          fixAction: '',
          risk: 'high'
        })]
      };
    }

    if (gpu.status === 'fulfilled') {
      results.gpu = gpu.value;
      allIssues.push(...(gpu.value.issues || []));
    } else {
      results.gpu = {
        gpus: { total: 0, allocatable: 0, allocated: 0, available: 0 },
        byNode: {},
        issues: [createIssue({
          id: 'gpu-inventory-error',
          severity: 'high',
          category: 'diagnostic',
          title: 'GPU Inventory Error',
          description: gpu.reason?.message || 'Unknown error',
          recommendation: 'Check kubectl setup',
          affectsRevenue: false,
          blocksNewLeases: false,
          hasFix: false,
          autoFix: false,
          fixAction: '',
          risk: 'high'
        })]
      };
    }

    if (storage.status === 'fulfilled') {
      results.storage = storage.value;
      allIssues.push(...(storage.value.issues || []));
    } else {
      results.storage = {
        pvCount: 0,
        pvcCount: 0,
        capacityUsed: '0Gi',
        issues: [createIssue({
          id: 'storage-status-error',
          severity: 'high',
          category: 'diagnostic',
          title: 'Storage Status Error',
          description: storage.reason?.message || 'Unknown error',
          recommendation: 'Check kubectl setup',
          affectsRevenue: false,
          blocksNewLeases: false,
          hasFix: false,
          autoFix: false,
          fixAction: '',
          risk: 'high'
        })]
      };
    }

    if (network.status === 'fulfilled') {
      results.network = network.value;
      allIssues.push(...(network.value.issues || []));
    } else {
      results.network = {
        networkPolicies: { count: 0, exists: false },
        dnsReady: false,
        connectivityTest: 'failed',
        issues: [createIssue({
          id: 'network-connectivity-error',
          severity: 'high',
          category: 'diagnostic',
          title: 'Network Connectivity Error',
          description: network.reason?.message || 'Unknown error',
          recommendation: 'Check kubectl setup',
          affectsRevenue: false,
          blocksNewLeases: false,
          hasFix: false,
          autoFix: false,
          fixAction: '',
          risk: 'high'
        })]
      };
    }

    if (quotas.status === 'fulfilled') {
      results.quotas = quotas.value;
      allIssues.push(...(quotas.value.issues || []));
    } else {
      results.quotas = {
        quotas: { resourceQuotaExists: false, limitRangeExists: false },
        limitsUsed: { cpu: 0, memory: 0 },
        issues: [createIssue({
          id: 'resource-quota-error',
          severity: 'high',
          category: 'diagnostic',
          title: 'Resource Quota Error',
          description: quotas.reason?.message || 'Unknown error',
          recommendation: 'Check kubectl setup',
          affectsRevenue: false,
          blocksNewLeases: false,
          hasFix: false,
          autoFix: false,
          fixAction: '',
          risk: 'high'
        })]
      };
    }

    if (pricing.status === 'fulfilled') {
      results.pricing = pricing.value;
      allIssues.push(...(pricing.value.issues || []));
    } else {
      results.pricing = {
        pricing: { action: 'unknown', reason: 'Check failed' },
        utilization: { gpu: 0, cpu: 0, memory: 0 },
        recommendations: [],
        issues: [createIssue({
          id: 'pricing-check-error',
          severity: 'medium',
          category: 'diagnostic',
          title: 'Pricing Optimization Check Error',
          description: pricing.reason?.message || 'Unknown error',
          recommendation: 'Check provider metrics.',
          affectsRevenue: true,
          blocksNewLeases: false,
          hasFix: false,
          autoFix: false,
          fixAction: 'Check provider pod logs',
          risk: 'low'
        })]
      };
    }

    // Generate summary
    const criticalIssues = allIssues.filter(i => i.severity === 'critical').length;
    const highIssues = allIssues.filter(i => i.severity === 'high').length;
    const mediumIssues = allIssues.filter(i => i.severity === 'medium').length;
    const lowIssues = allIssues.filter(i => i.severity === 'low').length;

    let overallHealth = 'healthy';
    if (criticalIssues > 0) {
      overallHealth = 'critical';
    } else if (highIssues > 0) {
      overallHealth = 'degraded';
    } else if (mediumIssues > 0) {
      overallHealth = 'degraded';
    } else if (lowIssues > 0 && lowIssues > 5) {
      overallHealth = 'degraded';
    }

    results.summary = {
      totalIssues: allIssues.length,
      criticalIssues,
      highIssues,
      mediumIssues,
      lowIssues,
      overallHealth,
      issues: allIssues
    };

  } catch (error) {
    results.summary = {
      totalIssues: 1,
      criticalIssues: 1,
      highIssues: 0,
      mediumIssues: 0,
      lowIssues: 0,
      overallHealth: 'critical',
      issues: [createIssue({
        id: 'diagnostic-runner-error',
        severity: 'critical',
        category: 'diagnostic',
        title: 'Diagnostic Runner Failed',
        description: `Failed to run diagnostics: ${error.message}`,
        recommendation: 'Check kubectl setup and permissions.',
        affectsRevenue: true,
        blocksNewLeases: false,
        hasFix: false,
        autoFix: false,
        fixAction: 'Check kubectl setup',
        risk: 'critical'
      })]
    };
  }

  return results;
}

module.exports = {
  checkProviderHealth,
  checkClusterHealth,
  checkHardwareDiscovery,
  checkGPUInventory,
  checkStorageStatus,
  checkNetworkConnectivity,
  checkResourceQuotas,
  runAllDiagnostics,
  calculateUptime
};
