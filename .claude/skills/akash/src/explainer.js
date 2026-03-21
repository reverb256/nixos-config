/**
 * Explanation Generator
 *
 * Generates human-readable reports with ASCII topology diagrams
 * for cluster state and educational content about Akash concepts.
 */

/**
 * Generate comprehensive markdown audit report
 *
 * @param {Object} clusterState - Current cluster state
 * @param {Array} issues - Array of detected issues
 * @param {Array} recommendations - Array of recommendations
 * @param {string} visualTopology - ASCII topology diagram (optional)
 * @param {Object} metadata - Audit metadata (duration, command)
 * @returns {string} Formatted markdown report
 */
function generateReport(clusterState, issues, recommendations, visualTopology = null, metadata = {}) {
  const timestamp = new Date().toISOString();
  const duration = metadata.duration ? `${(metadata.duration / 1000).toFixed(2)}s` : 'N/A';
  const command = metadata.command || 'audit';

  let report = '# Akash Provider Audit Report\n\n';
  report += `**Generated:** ${timestamp}\n`;
  report += `**Command:** \`${command}\`\n`;
  report += `**Duration:** ${duration}\n\n`;

  // Executive Summary
  report += '## Executive Summary\n\n';
  const summaryEmoji = getSummaryEmoji(clusterState, issues);
  const summaryText = generateSummaryText(clusterState, issues);
  report += `${summaryEmoji} ${summaryText}\n\n`;

  // Cluster Topology
  if (visualTopology) {
    report += '## Cluster Topology\n\n';
    report += '```\n';
    report += visualTopology;
    report += '\n```\n\n';
  }

  // Provider Status
  if (clusterState.provider) {
    report += '## Provider Status\n\n';
    report += generateProviderStatus(clusterState.provider);
    report += '\n';
  }

  // Issues Found
  report += '## Issues Found\n\n';
  const categorized = categorizeBySeverity(issues);

  if (issues.length === 0) {
    report += '✅ No issues detected. Your provider is healthy!\n\n';
  } else {
    if (categorized.critical && categorized.critical.length > 0) {
      report += '### Critical 🔴\n\n';
      categorized.critical.forEach(issue => {
        report += formatIssue(issue);
      });
    }

    if (categorized.warnings && categorized.warnings.length > 0) {
      report += '### Warnings ⚠️\n\n';
      categorized.warnings.forEach(issue => {
        report += formatIssue(issue);
      });
    }

    if (categorized.informational && categorized.informational.length > 0) {
      report += '### Informational ℹ️\n\n';
      categorized.informational.forEach(issue => {
        report += formatIssue(issue);
      });
    }
  }

  // Recommendations
  report += '## Recommendations\n\n';
  if (recommendations && recommendations.length > 0) {
    recommendations.forEach((rec, index) => {
      report += `${index + 1}. ${rec}\n`;
    });
    report += '\n';
  } else {
    report += 'No specific recommendations at this time.\n\n';
  }

  return report;
}

/**
 * Generate ASCII cluster topology diagram
 *
 * @param {Object} clusterState - Current cluster state
 * @returns {string} ASCII diagram
 */
function generateTopology(clusterState) {
  if (!clusterState.nodes || clusterState.nodes.length === 0) {
    return 'No nodes found in cluster';
  }

  let topology = '';
  const boxWidth = 35;

  clusterState.nodes.forEach(node => {
    const status = node.ready ? '✅' : '🔴';
    const nodeName = node.name.padEnd(10);

    topology += '┌' + '─'.repeat(boxWidth - 2) + '┐\n';
    topology += `│ ${status} ${nodeName}                  │\n`;
    topology += '├' + '─'.repeat(boxWidth - 2) + '┤\n';

    if (node.gpus && node.gpus.total > 0) {
      const gpuBar = generateGPUBar(node.gpus);
      topology += `│ GPU: ${gpuBar.padEnd(24)} │\n`;
      topology += `│ Total: ${node.gpus.total}  ` +
                  `Used: ${node.gpus.used}  ` +
                  `Free: ${node.gpus.free}    │\n`;
    } else {
      topology += `│ No GPUs                        │\n`;
    }

    topology += '└' + '─'.repeat(boxWidth - 2) + '┘\n\n';
  });

  // Summary
  const totalGPUs = clusterState.nodes.reduce((sum, node) => sum + (node.gpus?.total || 0), 0);
  const totalUsed = clusterState.nodes.reduce((sum, node) => sum + (node.gpus?.used || 0), 0);
  const totalFree = clusterState.nodes.reduce((sum, node) => sum + (node.gpus?.free || 0), 0);

  topology += 'Cluster Summary:\n';
  topology += `  Nodes: ${clusterState.nodes.length}\n`;
  topology += `  Total GPUs: ${totalGPUs}\n`;
  topology += `  Used: ${totalUsed} | Free: ${totalFree}\n`;

  return topology;
}

/**
 * Explain Akash concepts with cluster-specific context
 *
 * @param {string} topic - Topic to explain (gpu, leases, provider, blockchain, network)
 * @param {Object} clusterState - Current cluster state for context
 * @returns {string} Educational content in markdown
 */
function explainTopic(topic, clusterState = {}) {
  const topics = {
    gpu: () => {
      let explanation = '## GPU Resources\n\n';
      explanation += '**GPU (Graphics Processing Unit)** is specialized hardware that ';
      explanation += 'excels at parallel processing tasks like AI inference, machine learning, ';
      explanation += 'and cryptocurrency mining.\n\n';

      explanation += '### In Akash Networks\n\n';
      explanation += 'GPUs are the primary compute resource that providers offer to tenants. ';
      explanation += 'Each GPU can be leased by a tenant for their workloads.\n\n';

      // Add cluster context
      if (clusterState.nodes) {
        const totalGPUs = clusterState.nodes.reduce((sum, node) => sum + (node.gpus?.total || 0), 0);
        const totalUsed = clusterState.nodes.reduce((sum, node) => sum + (node.gpus?.used || 0), 0);

        explanation += '### Your Cluster\n\n';
        explanation += `- **Total GPUs:** ${totalGPUs}\n`;
        explanation += `- **Currently Used:** ${totalUsed}\n`;
        explanation += `- **Available:** ${totalGPUs - totalUsed}\n\n`;

        if (clusterState.nodes.length > 0) {
          explanation += '#### GPU Distribution by Node:\n\n';
          clusterState.nodes.forEach(node => {
            if (node.gpus && node.gpus.total > 0) {
              explanation += `- **${node.name}:** ${node.gpus.total} GPUs `;
              explanation += `(${node.gpus.used} used, ${node.gpus.free} free)\n`;
            }
          });
        }
      }

      explanation += '\n### Related Topics\n';
      explanation += '- `leases` - How tenants acquire GPU resources\n';
      explanation += '- `provider` - Your role in the network\n';

      return explanation;
    },

    leases: () => {
      let explanation = '## Leases\n\n';
      explanation += 'A **Lease** in Akash represents a contract between a tenant (deployment) ';
      explanation += 'and a provider (you). When a tenant deploys a workload, they create a lease ';
      explanation += 'that reserves your resources.\n\n';

      explanation += '### Lease Lifecycle\n\n';
      explanation += '1. **Bid** - Tenant receives bids from providers\n';
      explanation += '2. **Create** - Tenant chooses a bid and creates a lease\n';
      explanation += '3. **Active** - Lease is active and workload is running\n';
      explanation += '4. **Closed** - Lease is closed and resources are freed\n\n';

      // Add cluster context
      if (clusterState.leases) {
        explanation += '### Your Active Leases\n\n';
        if (clusterState.leases.length === 0) {
          explanation += 'No active leases currently.\n';
        } else {
          clusterState.leases.forEach((lease, index) => {
            explanation += `${index + 1}. **DSeq:** ${lease.dseq}\n`;
            explanation += `   - Owner: ${lease.owner}\n`;
            explanation += `   - State: ${lease.state}\n`;
          });
        }
      }

      explanation += '\n### Related Topics\n';
      explanation += '- `gpu` - Resources being leased\n';
      explanation += '- `blockchain` - How leases are recorded on-chain\n';

      return explanation;
    },

    provider: () => {
      let explanation = '## Provider\n\n';
      explanation += 'A **Provider** in Akash Network is an infrastructure operator who ';
      explanation += 'contributes compute resources (GPUs, CPUs, storage) to the network and ';
      explanation += 'earns AKT tokens by hosting tenant workloads.\n\n';

      explanation += '### Your Responsibilities\n\n';
      explanation += '- **Maintain High Uptime** - Keep your provider online and responsive\n';
      explanation += '- **Monitor Resources** - Track GPU usage and temperatures\n';
      explanation += '- **Set Competitive Pricing** - Price your resources appropriately\n';
      explanation += '- **Ensure Security** - Keep your cluster and wallets secure\n\n';

      // Add cluster context
      if (clusterState.provider) {
        explanation += '### Your Provider Configuration\n\n';
        if (clusterState.provider.attributes) {
          explanation += '**Attributes:**\n';
          Object.entries(clusterState.provider.attributes).forEach(([key, value]) => {
            explanation += `- ${key}: ${value}\n`;
          });
        }
        if (clusterState.provider.hostUri) {
          explanation += `\n**Host URI:** ${clusterState.provider.hostUri}\n`;
        }
      }

      explanation += '\n### Related Topics\n';
      explanation += '- `gpu` - Resources you provide\n';
      explanation += '- `network` - How providers connect to tenants\n';

      return explanation;
    },

    blockchain: () => {
      let explanation = '## Blockchain Integration\n\n';
      explanation += 'Akash Network uses blockchain technology to create a trustless ';
      explanation += 'decentralized cloud marketplace. All provider attributes, bids, and ';
      explanation += 'leases are recorded on-chain.\n\n';

      explanation += '### Key Blockchain Concepts\n\n';
      explanation += '- **Provider Attributes** - Your capabilities are stored on-chain\n';
      explanation += '- **Bids** - You bid on deployment requests with your pricing\n';
      explanation += '- **Leases** - Active leases are tracked on-chain\n';
      explanation += '- **Settlement** - Payments are settled via smart contracts\n\n';

      explanation += '### Blockchain Benefits\n\n';
      explanation += '- **No Middlemen** - Direct tenant-provider relationship\n';
      explanation += '- **Transparent Pricing** - Market-driven pricing\n';
      explanation += '- **Immutable Records** - All transactions are recorded\n';
      explanation += '- **Permissionless** - Anyone can become a provider\n\n';

      explanation += '### Related Topics\n';
      explanation += '- `leases` - How blockchain tracks resource usage\n';
      explanation += '- `provider` - Your on-chain identity\n';

      return explanation;
    },

    network: () => {
      let explanation = '## Network Communication\n\n';
      explanation += 'Network connectivity is crucial for Akash providers. Your provider ';
      explanation += 'must be reachable by tenants for their deployments to communicate ';
      explanation += 'with your services.\n\n';

      explanation += '### Network Requirements\n\n';
      explanation += '- **Public IP** - Your provider needs a reachable public IP\n';
      explanation += '- **Open Ports** - Required ports must be accessible\n';
      explanation += '- **DNS Resolution** - Provider hostname should resolve\n';
      explanation += '- **Low Latency** - Better network performance = more bids\n\n';

      explanation += '### Port Forwarding\n\n';
      explanation += 'Common ports that need to be accessible:\n';
      explanation += '- **Port 8443** - Default provider port\n';
      explanation += '- **Port 30000-32767** - NodePort range for services\n';
      explanation += '- **SSH (22)** - For remote management\n\n';

      explanation += '### Related Topics\n';
      explanation += '- `provider` - Your provider\'s network configuration\n';
      explanation += '- `gpu` - Network considerations for GPU workloads\n';

      return explanation;
    }
  };

  const topicLower = topic.toLowerCase();
  if (topics[topicLower]) {
    return topics[topicLower]();
  }

  // Unknown topic
  return `## Topic Not Found\n\n` +
    `The topic "${topic}" is not available. Available topics:\n\n` +
    `- \`gpu\` - GPU resources and allocation\n` +
    `- \`leases\` - Tenant leases and deployment\n` +
    `- \`provider\` - Provider role and configuration\n` +
    `- \`blockchain\` - Blockchain integration concepts\n` +
    `- \`network\` - Network communication and setup\n`;
}

/**
 * Get related learning topics
 *
 * @param {string} topic - Current topic
 * @returns {Array<string>} Related topics
 */
function getRelatedTopics(topic) {
  const topicGraph = {
    gpu: ['leases', 'provider', 'network'],
    leases: ['gpu', 'blockchain', 'provider'],
    provider: ['gpu', 'network', 'blockchain'],
    blockchain: ['leases', 'provider'],
    network: ['provider', 'gpu']
  };

  const topicLower = topic.toLowerCase();
  return topicGraph[topicLower] || [];
}

// ========== Helper Functions ==========

/**
 * Map cluster state to emoji indicator
 *
 * @param {Object} clusterState - Current cluster state
 * @param {Array} issues - Array of issues
 * @returns {string} Emoji indicator
 */
function getSummaryEmoji(clusterState, issues) {
  if (!clusterState || !clusterState.nodes) {
    return '❓';
  }

  const criticalIssues = issues.filter(i => i.severity === 'error').length;
  const warnings = issues.filter(i => i.severity === 'warning').length;

  if (criticalIssues > 0) {
    return '🔴';
  }

  if (warnings > 0) {
    return '⚠️';
  }

  const allReady = clusterState.nodes.every(node => node.ready);
  return allReady ? '✅' : '⚠️';
}

/**
 * Generate one-line summary text
 *
 * @param {Object} clusterState - Current cluster state
 * @param {Array} issues - Array of issues
 * @returns {string} Summary text
 */
function generateSummaryText(clusterState, issues) {
  const nodeCount = clusterState.nodes?.length || 0;
  const readyCount = clusterState.nodes?.filter(n => n.ready).length || 0;
  const totalGPUs = clusterState.nodes?.reduce((sum, n) => sum + (n.gpus?.total || 0), 0) || 0;
  const usedGPUs = clusterState.nodes?.reduce((sum, n) => sum + (n.gpus?.used || 0), 0) || 0;
  const issueCount = issues.length;

  let summary = `Provider audit complete. `;
  summary += `${readyCount}/${nodeCount} nodes ready, `;
  summary += `${usedGPUs}/${totalGPUs} GPUs used`;

  if (issueCount > 0) {
    summary += `, ${issueCount} issues found`;
  } else {
    summary += ', no issues detected';
  }

  return summary + '.';
}

/**
 * Generate provider status section
 *
 * @param {Object} provider - Provider configuration
 * @returns {string} Formatted provider status
 */
function generateProviderStatus(provider) {
  let status = '';

  if (provider.attributes) {
    status += '**Attributes:**\n';
    Object.entries(provider.attributes).forEach(([key, value]) => {
      status += `- ${key}: \`${value}\`\n`;
    });
  }

  if (provider.hostUri) {
    status += `\n**Host URI:** ${provider.hostUri}\n`;
  }

  return status;
}

/**
 * Categorize issues by severity
 *
 * @param {Array} issues - Array of issues
 * @returns {Object} Categorized issues
 */
function categorizeBySeverity(issues) {
  const categorized = {
    critical: [],
    warnings: [],
    informational: []
  };

  if (!issues || issues.length === 0) {
    return categorized;
  }

  issues.forEach(issue => {
    switch (issue.severity) {
      case 'error':
        categorized.critical.push(issue);
        break;
      case 'warning':
        categorized.warnings.push(issue);
        break;
      case 'info':
        categorized.informational.push(issue);
        break;
      default:
        categorized.informational.push(issue);
    }
  });

  return categorized;
}

/**
 * Format a single issue
 *
 * @param {Object} issue - Issue object
 * @returns {string} Formatted issue
 */
function formatIssue(issue) {
  let formatted = '';

  if (issue.node) {
    formatted += `**${issue.node}:** `;
  }

  formatted += `${issue.message}\n`;

  if (issue.details) {
    formatted += `> ${issue.details}\n`;
  }

  formatted += '\n';
  return formatted;
}

/**
 * Generate GPU allocation bar chart
 *
 * @param {Object} gpus - GPU object with total, used, free, allocation
 * @returns {string} Bar chart string
 */
function generateGPUBar(gpus) {
  if (!gpus || gpus.total === 0) {
    return 'No GPUs';
  }

  const barLength = 20;
  const usedLength = Math.round((gpus.used / gpus.total) * barLength);

  let bar = '';
  for (let i = 0; i < barLength; i++) {
    if (i < usedLength) {
      bar += '██';
    } else {
      bar += '░░';
    }
  }

  return bar;
}

/**
 * Generate generic bar chart
 *
 * @param {number} count - Current value
 * @param {number} max - Maximum value
 * @param {number} length - Bar length in characters
 * @returns {string} Bar chart string
 */
function generateBar(count, max, length = 20) {
  if (max === 0) {
    return '░'.repeat(length);
  }

  const filled = Math.round((count / max) * length);
  return '█'.repeat(filled) + '░'.repeat(length - filled);
}

module.exports = {
  generateReport,
  generateTopology,
  explainTopic,
  getRelatedTopics,
  // Exported for testing
  getSummaryEmoji,
  generateSummaryText,
  generateProviderStatus,
  categorizeBySeverity,
  formatIssue,
  generateGPUBar,
  generateBar
};
