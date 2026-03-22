/**
 * Knowledge Base and Learning System
 *
 * Establishes baselines and detects patterns over time.
 * Maintains documentation for intelligent recommendations.
 *
 * Features:
 * - Baseline establishment and tracking
 * - Pattern detection from issue history
 * - Documentation retrieval and search
 * - Frequency analysis and recommendations
 */

const fs = require('fs');
const path = require('path');

// In-memory storage
let baseline = null;
let issueHistory = [];

/**
 * Load Akash documentation
 * @returns {Object} Documentation object
 */
function loadDocumentation() {
  const docsPath = path.join(__dirname, '../data/akash-docs.json');
  try {
    const content = fs.readFileSync(docsPath, 'utf8');
    return JSON.parse(content);
  } catch (error) {
    console.error('Failed to load documentation:', error.message);
    return {};
  }
}

/**
 * Establish initial cluster baseline
 * @param {Object} clusterState - Current cluster state
 * @returns {Object} Established baseline
 */
function establishBaseline(clusterState) {
  if (!clusterState) {
    throw new Error('Cluster state is required for baseline establishment');
  }

  baseline = {
    timestamp: new Date().toISOString(),
    topology: {
      nodeCount: clusterState.nodeCount || 0,
      gpuCount: clusterState.gpuCount || 0,
      gpuTypes: clusterState.gpuTypes || [],
      providerVersion: clusterState.providerVersion || 'unknown',
      clusterType: clusterState.clusterType || 'kubernetes'
    },
    resources: {
      totalCPU: clusterState.totalCPU || 0,
      totalMemory: clusterState.totalMemory || 0,
      totalGPU: clusterState.gpuCount || 0,
      allocatableGPU: clusterState.allocatableGPU || 0
    },
    provider: {
      namespace: clusterState.namespace || 'akash-services',
      status: clusterState.providerStatus || 'unknown',
      helmRelease: clusterState.helmRelease || 'unknown'
    },
    health: {
      providerHealthy: clusterState.providerHealthy || false,
      blockchainSynced: clusterState.blockchainSynced || false,
      biddingActive: clusterState.biddingActive || false
    }
  };

  return baseline;
}

/**
 * Get current baseline
 * @returns {Object|null} Current baseline or null if not established
 */
function getBaseline() {
  return baseline;
}

/**
 * Update baseline with new cluster state
 * @param {Object} clusterState - New cluster state
 * @returns {Object} Updated baseline
 */
function updateBaseline(clusterState) {
  if (!baseline) {
    return establishBaseline(clusterState);
  }

  // Update timestamp
  baseline.lastUpdated = new Date().toISOString();

  // Update topology if changed
  if (clusterState.nodeCount !== undefined) {
    baseline.topology.nodeCount = clusterState.nodeCount;
  }
  if (clusterState.gpuCount !== undefined) {
    baseline.topology.gpuCount = clusterState.gpuCount;
  }
  if (clusterState.gpuTypes !== undefined) {
    baseline.topology.gpuTypes = clusterState.gpuTypes;
  }
  if (clusterState.providerVersion !== undefined) {
    baseline.topology.providerVersion = clusterState.providerVersion;
  }

  // Update resources
  if (clusterState.totalCPU !== undefined) {
    baseline.resources.totalCPU = clusterState.totalCPU;
  }
  if (clusterState.totalMemory !== undefined) {
    baseline.resources.totalMemory = clusterState.totalMemory;
  }
  if (clusterState.allocatableGPU !== undefined) {
    baseline.resources.allocatableGPU = clusterState.allocatableGPU;
  }

  // Update health status
  if (clusterState.providerHealthy !== undefined) {
    baseline.health.providerHealthy = clusterState.providerHealthy;
  }
  if (clusterState.blockchainSynced !== undefined) {
    baseline.health.blockchainSynced = clusterState.blockchainSynced;
  }
  if (clusterState.biddingActive !== undefined) {
    baseline.health.biddingActive = clusterState.biddingActive;
  }

  return baseline;
}

/**
 * Add issue to history
 * @param {Object} issue - Issue object
 * @returns {Array} Updated issue history
 */
function addToHistory(issue) {
  if (!issue || !issue.id) {
    return issueHistory;
  }

  const historyEntry = {
    timestamp: new Date().toISOString(),
    issueId: issue.id,
    severity: issue.severity,
    category: issue.category,
    title: issue.title
  };

  issueHistory.push(historyEntry);
  return issueHistory;
}

/**
 * Detect patterns from issue history
 * @param {Array} issues - Current issues
 * @param {Array} history - Issue history (optional, uses internal history if not provided)
 * @returns {Object} Pattern analysis results
 */
function detectPatterns(issues, history = null) {
  const historyToAnalyze = history || issueHistory;
  const patterns = [];
  const frequency = {};

  // Count frequency of each issue type
  for (const entry of historyToAnalyze) {
    if (!frequency[entry.issueId]) {
      frequency[entry.issueId] = {
        count: 0,
        severity: entry.severity,
        category: entry.category,
        title: entry.title,
        firstSeen: entry.timestamp,
        lastSeen: entry.timestamp
      };
    }
    frequency[entry.issueId].count++;
    frequency[entry.issueId].lastSeen = entry.timestamp;
  }

  // Add current issues to frequency count
  for (const issue of issues) {
    if (!frequency[issue.id]) {
      frequency[issue.id] = {
        count: 0,
        severity: issue.severity,
        category: issue.category,
        title: issue.title,
        firstSeen: new Date().toISOString(),
        lastSeen: new Date().toISOString()
      };
    }
    frequency[issue.id].count++;
  }

  // Detect patterns: issues appearing 3+ times
  for (const [issueId, data] of Object.entries(frequency)) {
    if (data.count >= 3) {
      patterns.push({
        issueId,
        title: data.title,
        category: data.category,
        severity: data.severity,
        frequency: data.count,
        firstSeen: data.firstSeen,
        lastSeen: data.lastSeen,
        isRecurring: true,
        recommendation: generatePatternRecommendation(data)
      });
    }
  }

  // Detect severity escalation patterns
  const escalationPatterns = detectEscalationPatterns(historyToAnalyze);
  patterns.push(...escalationPatterns);

  // Detect category clustering patterns
  const categoryPatterns = detectCategoryPatterns(historyToAnalyze);
  patterns.push(...categoryPatterns);

  return {
    patterns,
    frequency,
    totalIssues: historyToAnalyze.length + issues.length,
    recurringIssueCount: patterns.length,
    timestamp: new Date().toISOString()
  };
}

/**
 * Detect escalation patterns (issues getting worse over time)
 * @param {Array} history - Issue history
 * @returns {Array} Escalation patterns
 */
function detectEscalationPatterns(history) {
  const patterns = [];
  const severityOrder = { low: 1, medium: 2, high: 3, critical: 4 };

  // Group by issue ID
  const grouped = {};
  for (const entry of history) {
    if (!grouped[entry.issueId]) {
      grouped[entry.issueId] = [];
    }
    grouped[entry.issueId].push(entry);
  }

  // Check for escalation
  for (const [issueId, entries] of Object.entries(grouped)) {
    if (entries.length < 2) continue;

    const sortedEntries = [...entries].sort((a, b) =>
      new Date(a.timestamp) - new Date(b.timestamp)
    );

    let hasEscalation = false;
    for (let i = 1; i < sortedEntries.length; i++) {
      const prevSeverity = severityOrder[sortedEntries[i - 1].severity] || 0;
      const currSeverity = severityOrder[sortedEntries[i].severity] || 0;

      if (currSeverity > prevSeverity) {
        hasEscalation = true;
        break;
      }
    }

    if (hasEscalation) {
      patterns.push({
        issueId,
        title: entries[0].title,
        category: entries[0].category,
        patternType: 'escalation',
        severity: 'high',
        frequency: entries.length,
        firstSeen: sortedEntries[0].timestamp,
        lastSeen: sortedEntries[sortedEntries.length - 1].timestamp,
        recommendation: `Issue '${entries[0].title}' is escalating in severity. Address immediately to prevent service impact.`
      });
    }
  }

  return patterns;
}

/**
 * Detect category clustering patterns
 * @param {Array} history - Issue history
 * @returns {Array} Category patterns
 */
function detectCategoryPatterns(history) {
  const patterns = [];
  const categoryCount = {};

  // Count issues per category
  for (const entry of history) {
    if (!categoryCount[entry.category]) {
      categoryCount[entry.category] = 0;
    }
    categoryCount[entry.category]++;
  }

  // Detect high-frequency categories
  for (const [category, count] of Object.entries(categoryCount)) {
    if (count >= 5) {
      patterns.push({
        issueId: `category-${category}`,
        title: `High Frequency of ${category} Issues`,
        category,
        patternType: 'category-cluster',
        severity: 'medium',
        frequency: count,
        recommendation: `Cluster experiencing recurring ${category} issues. Review ${category} configuration and consider preventive measures.`
      });
    }
  }

  return patterns;
}

/**
 * Generate recommendation for recurring pattern
 * @param {Object} data - Pattern data
 * @returns {string} Recommendation text
 */
function generatePatternRecommendation(data) {
  const docs = getDocumentation(data.category);
  let recommendation = `Issue '${data.title}' has occurred ${data.count} times.`;

  if (docs && docs.content) {
    recommendation += ` Reference: ${docs.content.substring(0, 100)}...`;
  }

  recommendation += ' Consider implementing preventive measures or reviewing configuration.';

  return recommendation;
}

/**
 * Get documentation for a topic
 * @param {string} topic - Topic identifier (e.g., 'provider', 'gpu', 'network')
 * @returns {Object|null} Documentation object or null if not found
 */
function getDocumentation(topic) {
  const docs = loadDocumentation();

  // Direct topic match
  if (docs[topic]) {
    return {
      topic,
      ...docs[topic]
    };
  }

  // Search in subcategories
  for (const [category, subcategories] of Object.entries(docs)) {
    if (subcategories[topic]) {
      return {
        category,
        topic,
        ...subcategories[topic]
      };
    }
  }

  return null;
}

/**
 * Search documentation for relevant content
 * @param {string} query - Search query
 * @returns {Array} Array of matching documentation topics
 */
function searchDocumentation(query) {
  if (!query || typeof query !== 'string') {
    return [];
  }

  const docs = loadDocumentation();
  const results = [];
  const queryLower = query.toLowerCase();

  for (const [category, subcategories] of Object.entries(docs)) {
    for (const [topic, data] of Object.entries(subcategories)) {
      const title = data.title || '';
      const content = data.content || '';
      const related = data.related || [];

      // Search in title and content
      if (title.toLowerCase().includes(queryLower) ||
          content.toLowerCase().includes(queryLower)) {
        results.push({
          category,
          topic,
          title,
          content: content.substring(0, 200) + (content.length > 200 ? '...' : ''),
          related,
          relevance: calculateRelevance(query, title, content)
        });
      }

      // Search in related topics
      for (const relatedTopic of related) {
        if (relatedTopic.toLowerCase().includes(queryLower)) {
          if (!results.find(r => r.topic === topic)) {
            results.push({
              category,
              topic,
              title,
              content: content.substring(0, 200) + (content.length > 200 ? '...' : ''),
              related,
              relevance: calculateRelevance(query, title, content)
            });
          }
        }
      }
    }
  }

  // Sort by relevance
  results.sort((a, b) => b.relevance - a.relevance);

  return results;
}

/**
 * Calculate relevance score for search result
 * @param {string} query - Search query
 * @param {string} title - Document title
 * @param {string} content - Document content
 * @returns {number} Relevance score (0-100)
 */
function calculateRelevance(query, title, content) {
  const queryLower = query.toLowerCase();
  const titleLower = title.toLowerCase();
  const contentLower = content.toLowerCase();

  let score = 0;

  // Exact match in title (highest relevance)
  if (titleLower === queryLower) {
    score += 100;
  }

  // Query words in title
  const queryWords = queryLower.split(/\s+/);
  for (const word of queryWords) {
    if (titleLower.includes(word)) {
      score += 20;
    }
    if (contentLower.includes(word)) {
      score += 5;
    }
  }

  return Math.min(score, 100);
}

/**
 * Clear issue history (for testing)
 */
function clearHistory() {
  issueHistory = [];
}

/**
 * Get issue history
 * @returns {Array} Issue history
 */
function getHistory() {
  return issueHistory;
}

/**
 * Reset baseline (for testing)
 */
function resetBaseline() {
  baseline = null;
}

/**
 * Suggest pricing adjustments based on utilization
 * @param {Object} utilization - Current resource utilization
 * @returns {Object} Pricing recommendation
 */
function suggestPriceAdjustment(utilization = {}) {
  const {
    gpu = 0,
    cpu = 0,
    memory = 0
  } = utilization;

  // Determine overall utilization (weighted toward GPU as most valuable)
  const overallUtil = (gpu * 0.6) + (cpu * 0.25) + (memory * 0.15);

  let recommendation = {
    action: 'maintain',
    reason: '',
    suggestedDiscount: 0,
    suggestedPremium: 0,
    priority: 'low',
    utilization: {
      gpu,
      cpu,
      memory,
      overall: Math.round(overallUtil * 100) / 100
    }
  };

  // Low utilization: suggest lowering prices
  if (overallUtil < 0.3) {
    recommendation.action = 'lower_prices';
    recommendation.reason = `Low utilization (${Math.round(overallUtil * 100)}% GPU, ${Math.round(cpu * 100)}% CPU). Consider 25% discount to attract tenants.`;
    recommendation.suggestedDiscount = 0.25;
    recommendation.priority = overallUtil < 0.1 ? 'high' : 'medium';
  }
  // High utilization: suggest raising prices
  else if (overallUtil > 0.6) {
    recommendation.action = 'raise_prices';
    recommendation.reason = `High utilization (${Math.round(overallUtil * 100)}% GPU, ${Math.round(cpu * 100)}% CPU). Consider ${overallUtil > 0.9 ? '50' : '25'}% premium.`;
    recommendation.suggestedPremium = overallUtil > 0.9 ? 0.50 : 0.25;
    recommendation.priority = overallUtil > 0.9 ? 'high' : 'medium';
  }
  // Medium utilization: maintain current pricing
  else {
    recommendation.action = 'maintain';
    recommendation.reason = `Utilization in healthy range (${Math.round(overallUtil * 100)}% GPU, ${Math.round(cpu * 100)}% CPU). Current pricing is appropriate.`;
    recommendation.priority = 'low';
  }

  return recommendation;
}

/**
 * Calculate optimal pricing based on current baseline
 * @returns {Object} Pricing recommendations
 */
function calculateOptimalPricing() {
  if (!baseline) {
    return {
      error: 'Baseline not established. Run diagnostics first.'
    };
  }

  const { resources } = baseline;
  if (!resources.allocatableGPU || resources.allocatableGPU === 0) {
    return {
      error: 'No GPU resources detected. Cannot calculate GPU pricing.'
    };
  }

  // Estimate utilization (would need real-time data in production)
  const gpuUtil = 0; // TODO: Fetch from metrics
  const cpuUtil = resources.totalCPU ? 0.38 : 0; // From cluster status
  const memUtil = resources.totalMemory ? 0.35 : 0;

  return suggestPriceAdjustment({
    gpu: gpuUtil,
    cpu: cpuUtil,
    memory: memUtil
  });
}

module.exports = {
  establishBaseline,
  getBaseline,
  updateBaseline,
  detectPatterns,
  addToHistory,
  getDocumentation,
  searchDocumentation,
  clearHistory,
  getHistory,
  resetBaseline,
  suggestPriceAdjustment,
  calculateOptimalPricing
};
