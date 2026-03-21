/**
 * Auto-Fix Coordinator
 *
 * Main entry point for automatic fix operations with permission system.
 * Decides whether to execute fixes automatically or require user approval.
 *
 * Fix Categories:
 * - Automatic (low-risk): pod-delete, restart, scale
 * - Permission-required (high-risk): provider-config, resource-delete
 *
 * Decision Logic:
 * 1. Check if issue has a fix action
 * 2. Check if fix type is automatic or requires permission
 * 3. Check autoFix option flag
 * 4. Check issue.autoFix flag
 * 5. Execute or return permission requirement
 */

const {
  deletePod,
  restartDeployment,
  scaleDeployment,
  deletePods
} = require('./utils/fixes');

/**
 * Determine if a fix action is automatic (low-risk) or requires permission (high-risk)
 * @param {string} fixAction - The fix action type
 * @returns {boolean} True if automatic, false if requires permission
 */
function isAutomaticFix(fixAction) {
  const automaticFixes = ['pod-delete', 'restart', 'scale'];
  return automaticFixes.includes(fixAction);
}

/**
 * Determine if a fix action is high-risk and always requires permission
 * @param {string} fixAction - The fix action type
 * @returns {boolean} True if high-risk
 */
function isHighRiskFix(fixAction) {
  const highRiskFixes = ['provider-config', 'resource-delete'];
  return highRiskFixes.includes(fixAction);
}

/**
 * Execute an automatic fix
 * @param {Object} issue - Issue object with fixAction
 * @param {Object} options - Options for the fix operation
 * @returns {Object} Result object { success, action, output, error, requiredPermission }
 */
function executeAutomaticFix(issue, options) {
  const { fixAction } = issue;
  const { namespace } = options;

  try {
    switch (fixAction) {
      case 'pod-delete':
        if (!options.podName) {
          return {
            success: false,
            action: fixAction,
            error: 'Missing required parameter: podName',
            requiredPermission: false
          };
        }
        return {
          ...deletePod(namespace, options.podName),
          action: fixAction,
          requiredPermission: false
        };

      case 'restart':
        if (!options.deploymentName) {
          return {
            success: false,
            action: fixAction,
            error: 'Missing required parameter: deploymentName',
            requiredPermission: false
          };
        }
        return {
          ...restartDeployment(
            namespace,
            options.deploymentName,
            options.resourceType
          ),
          action: fixAction,
          requiredPermission: false
        };

      case 'scale':
        if (!options.deploymentName || options.replicas === undefined) {
          return {
            success: false,
            action: fixAction,
            error: 'Missing required parameters: deploymentName, replicas',
            requiredPermission: false
          };
        }
        return {
          ...scaleDeployment(
            namespace,
            options.deploymentName,
            options.replicas,
            options.resourceType
          ),
          action: fixAction,
          requiredPermission: false
        };

      default:
        return {
          success: false,
          action: fixAction,
          error: `Unknown automatic fix action: ${fixAction}`,
          requiredPermission: true
        };
    }
  } catch (error) {
    return {
      success: false,
      action: fixAction,
      error: error.message,
      requiredPermission: false
    };
  }
}

/**
 * Main entry point for attempting automatic fixes
 *
 * Decision logic:
 * 1. If issue has no fixAction → return permission required
 * 2. If fix is high-risk (provider-config, resource-delete) → return permission required
 * 3. If autoFix option is false → return permission required
 * 4. If issue.autoFix is false/undefined → return permission required
 * 5. Otherwise execute automatic fix
 *
 * @param {Object} issue - Issue object from diagnostics
 * @param {Object} options - Options for the fix operation
 * @param {boolean} options.autoFix - Whether to execute automatic fixes (default: false)
 * @param {string} options.namespace - Kubernetes namespace
 * @param {string} [options.podName] - Pod name (for pod-delete)
 * @param {string} [options.deploymentName] - Deployment name (for restart, scale)
 * @param {number} [options.replicas] - Replica count (for scale)
 * @param {string} [options.resourceType] - Resource type (default: 'deployment')
 * @param {string} [options.resourceName] - Resource name (for resource-delete)
 * @returns {Object} Result object { success, action, output, error, requiredPermission, reason }
 */
function attemptAutoFix(issue, options = {}) {
  // Check if issue has a fix action
  if (!issue.fixAction) {
    return {
      success: false,
      requiredPermission: true,
      reason: 'No fix action available for this issue'
    };
  }

  // High-risk fixes always require permission
  if (isHighRiskFix(issue.fixAction)) {
    return {
      success: false,
      action: issue.fixAction,
      requiredPermission: true,
      reason: 'high-risk operation requires user approval'
    };
  }

  // Check if fix action is valid (automatic or unknown)
  if (!isAutomaticFix(issue.fixAction)) {
    return {
      success: false,
      action: issue.fixAction,
      requiredPermission: true,
      reason: 'Unknown fix action requires user approval'
    };
  }

  // Check if autoFix is enabled in options
  if (options.autoFix !== true) {
    return {
      success: false,
      action: issue.fixAction,
      requiredPermission: true,
      reason: 'autoFix disabled (enable with autoFix: true option)'
    };
  }

  // Check if issue is marked as auto-fixable
  if (issue.autoFix !== true) {
    return {
      success: false,
      action: issue.fixAction,
      requiredPermission: true,
      reason: 'Issue not marked for automatic fixing (autoFix: false)'
    };
  }

  // Execute automatic fix
  return executeAutomaticFix(issue, options);
}

module.exports = {
  attemptAutoFix,
  isAutomaticFix,
  isHighRiskFix,
  executeAutomaticFix
};
