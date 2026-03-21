/**
 * Kubernetes Kubectl Utility Functions
 *
 * Safe wrapper around kubectl commands using execFileSync
 * to avoid shell injection vulnerabilities.
 */

const { execFileSync } = require('child_process');
const os = require('os');

/**
 * Execute kubectl command with given arguments
 * @param {string[]} args - Arguments to pass to kubectl
 * @param {Object} options - Options for execFileSync
 * @returns {string} Command output
 * @throws {Error} If command fails
 */
function kubectl(args, options = {}) {
  const defaultOptions = {
    encoding: 'utf-8',
    maxBuffer: 10 * 1024 * 1024, // 10MB
    ...options
  };

  try {
    const output = execFileSync('kubectl', args, defaultOptions);
    return output.trim();
  } catch (error) {
    // Return error output if available
    if (error.stderr) {
      throw new Error(`kubectl ${args.join(' ')} failed: ${error.stderr.trim()}`);
    }
    throw error;
  }
}

/**
 * Get pods in a namespace with optional label selector
 * @param {string} namespace - Kubernetes namespace
 * @param {string} labelSelector - Label selector (optional)
 * @returns {Object[]} Array of pod objects
 */
function getPods(namespace, labelSelector = null) {
  const args = ['get', 'pods', '-n', namespace, '-o', 'json'];

  if (labelSelector) {
    args.push('-l', labelSelector);
  }

  const output = kubectl(args);
  const data = JSON.parse(output);
  return data.items;
}

/**
 * Get logs from a pod
 * @param {string} namespace - Kubernetes namespace
 * @param {string} podName - Name of the pod
 * @param {number} tailLines - Number of lines to tail from end (optional)
 * @returns {string} Pod logs
 */
function getPodLogs(namespace, podName, tailLines = null) {
  const args = ['logs', podName, '-n', namespace];

  if (tailLines) {
    args.push('--tail', String(tailLines));
  }

  return kubectl(args);
}

/**
 * Describe a node to get detailed information
 * @param {string} nodeName - Name of the node
 * @returns {Object} Node description
 */
function describeNode(nodeName) {
  const args = ['describe', 'node', nodeName];
  const output = kubectl(args);
  return output;
}

/**
 * Get all nodes in the cluster
 * @returns {Object[]} Array of node objects
 */
function getNodes() {
  const args = ['get', 'nodes', '-o', 'json'];
  const output = kubectl(args);
  const data = JSON.parse(output);
  return data.items;
}

/**
 * Get a configmap by name in a namespace
 * @param {string} namespace - Kubernetes namespace
 * @param {string} name - Configmap name
 * @returns {Object} Configmap data
 */
function getConfigMap(namespace, name) {
  const args = ['get', 'configmap', name, '-n', namespace, '-o', 'json'];
  const output = kubectl(args);
  const data = JSON.parse(output);
  return data;
}

/**
 * Parse provider metrics from pod logs
 * Extracts GPU, CPU, and memory utilization information
 * @param {string} namespace - Provider namespace
 * @returns {Object} Parsed metrics { gpu, cpu, memory }
 */
function getProviderMetrics(namespace) {
  try {
    const pods = getPods(namespace, 'app.kubernetes.io/name=akash-provider');

    if (pods.length === 0) {
      return { gpu: null, cpu: null, memory: null };
    }

    const podName = pods[0].metadata.name;
    const logs = getPodLogs(namespace, podName, 100);

    const metrics = {
      gpu: [],
      cpu: null,
      memory: null
    };

    // Parse GPU metrics (example patterns)
    const gpuPattern = /GPU (\d+): (\d+)% utilization/i;
    const gpuMatches = logs.matchAll(new RegExp(gpuPattern, 'gi'));
    for (const match of gpuMatches) {
      metrics.gpu.push({
        id: match[1],
        utilization: parseInt(match[2], 10)
      });
    }

    // Parse CPU metric
    const cpuPattern = /CPU: ([\d.]+)%/i;
    const cpuMatch = logs.match(cpuPattern);
    if (cpuMatch) {
      metrics.cpu = parseFloat(cpuMatch[1]);
    }

    // Parse memory metric
    const memPattern = /Memory: ([\d.]+)%/i;
    const memMatch = logs.match(memPattern);
    if (memMatch) {
      metrics.memory = parseFloat(memMatch[1]);
    }

    return metrics;
  } catch (error) {
    // If metrics parsing fails, return null values
    return { gpu: null, cpu: null, memory: null };
  }
}

/**
 * Check if kubectl is available and configured
 * @returns {boolean} True if kubectl is working
 */
function isKubectlAvailable() {
  try {
    kubectl(['version', '--client']);
    return true;
  } catch (error) {
    return false;
  }
}

/**
 * Get cluster version info
 * @returns {Object} Cluster version information
 */
function getClusterInfo() {
  try {
    const args = ['cluster-info'];
    const output = kubectl(args);
    return output;
  } catch (error) {
    throw new Error(`Failed to get cluster info: ${error.message}`);
  }
}

module.exports = {
  kubectl,
  getPods,
  getPodLogs,
  describeNode,
  getNodes,
  getConfigMap,
  getProviderMetrics,
  isKubectlAvailable,
  getClusterInfo
};
