/**
 * Kubernetes Fix Operations
 *
 * Safe kubectl-based fix operations for common Kubernetes issues.
 * All functions return structured objects with success/error information.
 *
 * Operations:
 * - Pod deletion (low-risk)
 * - Deployment restart (low-risk)
 * - Scaling operations (low-risk)
 * - Batch pod deletion (low-risk)
 */

const { kubectl } = require('./kubectl');

/**
 * Delete a pod from a namespace
 * @param {string} namespace - Kubernetes namespace
 * @param {string} podName - Name of the pod to delete
 * @returns {Object} Result object { success, output, error }
 */
function deletePod(namespace, podName) {
  try {
    const output = kubectl(['delete', 'pod', podName, '-n', namespace]);
    return {
      success: true,
      output
    };
  } catch (error) {
    return {
      success: false,
      error: error.message
    };
  }
}

/**
 * Restart a deployment using rollout restart
 * @param {string} namespace - Kubernetes namespace
 * @param {string} deploymentName - Name of the deployment to restart
 * @param {string} resourceType - Type of resource (default: 'deployment')
 * @returns {Object} Result object { success, output, error }
 */
function restartDeployment(namespace, deploymentName, resourceType = 'deployment') {
  try {
    const output = kubectl([
      'rollout', 'restart', resourceType, deploymentName, '-n', namespace
    ]);
    return {
      success: true,
      output
    };
  } catch (error) {
    return {
      success: false,
      error: error.message
    };
  }
}

/**
 * Scale a deployment or statefulset to a specific replica count
 * @param {string} namespace - Kubernetes namespace
 * @param {string} deploymentName - Name of the deployment to scale
 * @param {number} replicas - Target replica count
 * @param {string} resourceType - Type of resource (default: 'deployment')
 * @returns {Object} Result object { success, output, error }
 */
function scaleDeployment(namespace, deploymentName, replicas, resourceType = 'deployment') {
  try {
    const output = kubectl([
      'scale', resourceType, deploymentName,
      `--replicas=${replicas}`,
      '-n', namespace
    ]);
    return {
      success: true,
      output
    };
  } catch (error) {
    return {
      success: false,
      error: error.message
    };
  }
}

/**
 * Delete multiple pods by label selector
 * @param {string} namespace - Kubernetes namespace
 * @param {string} labelSelector - Label selector (e.g., 'app=gpu-miner')
 * @returns {Object} Result object { success, output, error }
 */
function deletePods(namespace, labelSelector) {
  try {
    const output = kubectl([
      'delete', 'pod', '-l', labelSelector, '-n', namespace
    ]);
    return {
      success: true,
      output
    };
  } catch (error) {
    return {
      success: false,
      error: error.message
    };
  }
}

module.exports = {
  deletePod,
  restartDeployment,
  scaleDeployment,
  deletePods
};
