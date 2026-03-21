#!/usr/bin/env node

/**
 * Akash Network Provider Assistant
 *
 * Main entry point for intelligent Akash provider diagnostics and management.
 * Routes commands to appropriate diagnostic and fix modules.
 */

const diagnostics = require('./diagnostics');
const prioritizer = require('./prioritizer');
const explainer = require('./explainer');
const autoFix = require('./auto-fix');
const knowledge = require('./knowledge');

/**
 * Handle incoming commands from AI agents
 *
 * @param {string} command - Command to execute (check, audit, fix, explain, monitor)
 * @param {object} options - Command options and context
 * @returns {object} Command result with data and status
 */
function handleCommand(command, options = {}) {
  const commands = {
    'check': runQuickCheck,
    'audit': runFullAudit,
    'fix': runAutoFix,
    'explain': runExplanation,
    'monitor': runMonitoring,
    'default': runQuickCheck
  };

  const handler = commands[command] || commands['default'];

  try {
    return handler(options);
  } catch (error) {
    return {
      success: false,
      error: error.message,
      command: command
    };
  }
}

/**
 * Run quick health check
 *
 * @param {object} options - Check options
 * @returns {object} Check results
 */
function runQuickCheck(options = {}) {
  const results = diagnostics.quickCheck(options);
  return {
    success: true,
    command: 'check',
    data: results,
    timestamp: new Date().toISOString()
  };
}

/**
 * Run full provider audit
 *
 * @param {object} options - Audit options
 * @returns {object} Audit results with prioritized issues
 */
function runFullAudit(options = {}) {
  const diagnosticsResults = diagnostics.fullAudit(options);
  const prioritizedIssues = prioritizer.rankIssues(diagnosticsResults.issues);

  return {
    success: true,
    command: 'audit',
    data: {
      diagnostics: diagnosticsResults,
      issues: prioritizedIssues,
      summary: generateAuditSummary(prioritizedIssues)
    },
    timestamp: new Date().toISOString()
  };
}

/**
 * Run automatic fixes
 *
 * @param {object} options - Fix options (dryRun, categories, etc.)
 * @returns {object} Fix results
 */
function runAutoFix(options = {}) {
  const { dryRun = false, categories = [] } = options;

  // Run diagnostics first to identify issues
  const diagnosticsResults = diagnostics.fullAudit(options);
  const prioritizedIssues = prioritizer.rankIssues(diagnosticsResults.issues);

  // Filter by categories if specified
  const targetIssues = categories.length > 0
    ? prioritizedIssues.filter(issue => categories.includes(issue.category))
    : prioritizedIssues;

  // Attempt fixes
  const fixResults = autoFix.attemptFixes(targetIssues, { dryRun });

  // Learn from results
  knowledge.recordFixResults(fixResults);

  return {
    success: true,
    command: 'fix',
    data: {
      dryRun: dryRun,
      attempted: fixResults.attempted,
      succeeded: fixResults.succeeded,
      failed: fixResults.failed,
      results: fixResults
    },
    timestamp: new Date().toISOString()
  };
}

/**
 * Generate explanation report
 *
 * @param {object} options - Explanation options
 * @returns {object} Explanation report
 */
function runExplanation(options = {}) {
  const diagnosticsResults = diagnostics.fullAudit(options);
  const prioritizedIssues = prioritizer.rankIssues(diagnosticsResults.issues);

  const explanation = explainer.generateReport({
    diagnostics: diagnosticsResults,
    issues: prioritizedIssues,
    format: options.format || 'markdown'
  });

  return {
    success: true,
    command: 'explain',
    data: explanation,
    timestamp: new Date().toISOString()
  };
}

/**
 * Run real-time monitoring
 *
 * @param {object} options - Monitoring options
 * @returns {object} Monitoring session info
 */
function runMonitoring(options = {}) {
  const { duration = 300, interval = 5 } = options;

  return {
    success: true,
    command: 'monitor',
    data: {
      message: 'Monitoring session started',
      duration: duration,
      interval: interval,
      metricsEndpoint: '/var/log/akash-assistant/metrics.log'
    },
    timestamp: new Date().toISOString()
  };
}

/**
 * Generate audit summary
 *
 * @param {array} issues - Prioritized issues array
 * @returns {object} Summary statistics
 */
function generateAuditSummary(issues) {
  const bySeverity = issues.reduce((acc, issue) => {
    acc[issue.severity] = (acc[issue.severity] || 0) + 1;
    return acc;
  }, {});

  return {
    total: issues.length,
    critical: bySeverity.P0 || 0,
    high: bySeverity.P1 || 0,
    medium: bySeverity.P2 || 0,
    low: bySeverity.P3 || 0
  };
}

// Module exports for external usage
module.exports = {
  handleCommand,
  runDiagnostics: diagnostics.fullAudit,
  prioritizeIssues: prioritizer.rankIssues,
  generateReport: explainer.generateReport,
  attemptAutoFix: autoFix.attemptFixes
};

// Direct execution support for testing
if (require.main === module) {
  const args = process.argv.slice(2);
  const command = args[0] || 'check';

  const result = handleCommand(command);
  console.log(JSON.stringify(result, null, 2));
}
