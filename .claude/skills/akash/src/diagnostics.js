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

const { getPods, getPodLogs } = require('./utils/kubectl');

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

module.exports = {
  checkProviderHealth,
  calculateUptime
};
