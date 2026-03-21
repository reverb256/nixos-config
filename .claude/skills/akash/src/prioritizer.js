/**
 * Prioritization System
 *
 * Issue ranking and impact analysis for detected provider problems.
 * Assigns severity levels (P0-P3) based on:
 *
 * - Impact on provider availability
 * - Tenant deployment failures
 * - Resource waste or inefficiency
 * - Security vulnerabilities
 * - Performance degradation
 *
 * Priority Levels:
 * - P0: Critical - Provider down or completely non-functional
 * - P1: High - Major functionality broken, multiple tenants affected
 * - P2: Medium - Partial degradation, single-tenant issues
 * - P3: Low - Optimization opportunities, cosmetic issues
 */

/**
 * Base severity scores
 */
const BASE_SCORES = {
  critical: 100,
  high: 50,
  medium: 20,
  low: 5
};

/**
 * Impact modifiers
 */
const IMPACT_MODIFIERS = {
  revenue: 20,
  'multiple-nodes': 15,
  'blocks-leases': 25
};

/**
 * Urgency modifiers
 */
const URGENCY_MODIFIERS = {
  degrading: 10,
  'user-complaints': 15
};

/**
 * Calculate priority score for an issue
 *
 * @param {Object} issue - Issue object with severity, impact, and urgency
 * @param {string} issue.severity - Severity level (critical, high, medium, low)
 * @param {string[]} issue.impact - Impact modifiers
 * @param {string[]} issue.urgency - Urgency modifiers
 * @returns {number} Total priority score
 */
function calculateScore(issue) {
  const severity = issue.severity?.toLowerCase() || 'low';
  const impacts = issue.impact || [];
  const urgencies = issue.urgency || [];

  // Start with base severity score
  let score = BASE_SCORES[severity] || BASE_SCORES.low;

  // Add impact modifiers
  impacts.forEach(impact => {
    const modifier = IMPACT_MODIFIERS[impact.toLowerCase()];
    if (modifier) {
      score += modifier;
    }
  });

  // Add urgency modifiers
  urgencies.forEach(urgency => {
    const modifier = URGENCY_MODIFIERS[urgency.toLowerCase()];
    if (modifier) {
      score += modifier;
    }
  });

  return score;
}

/**
 * Prioritize issues by score and assign priority numbers
 *
 * @param {Object[]} issues - Array of issue objects
 * @returns {Object[]} Sorted issues with priority and score fields added
 */
function prioritizeIssues(issues) {
  if (!issues || issues.length === 0) {
    return [];
  }

  // Calculate scores for all issues
  const issuesWithScores = issues.map(issue => ({
    ...issue,
    score: calculateScore(issue)
  }));

  // Sort by score descending (highest priority first)
  const sorted = issuesWithScores.sort((a, b) => b.score - a.score);

  // Assign priority numbers (1-based)
  return sorted.map((issue, index) => ({
    ...issue,
    priority: index + 1
  }));
}

/**
 * Categorize issues by severity level
 *
 * @param {Object[]} issues - Array of issue objects
 * @returns {Object} Object with critical, high, medium, low arrays
 */
function categorizeIssues(issues) {
  if (!issues || issues.length === 0) {
    return {
      critical: [],
      high: [],
      medium: [],
      low: []
    };
  }

  const categories = {
    critical: [],
    high: [],
    medium: [],
    low: []
  };

  issues.forEach(issue => {
    const severity = issue.severity?.toLowerCase() || 'low';
    if (categories[severity]) {
      categories[severity].push(issue);
    }
  });

  return categories;
}

module.exports = {
  calculateScore,
  prioritizeIssues,
  categorizeIssues
};
