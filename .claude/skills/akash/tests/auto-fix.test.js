/**
 * Auto-Fix Module Tests
 *
 * Test suite for automatic fix operations with permission system
 */

const {
  deletePod,
  restartDeployment,
  scaleDeployment,
  deletePods
} = require('../src/utils/fixes');
const {
  attemptAutoFix
} = require('../src/auto-fix');
const { kubectl } = require('../src/utils/kubectl');

// Mock kubectl utilities
jest.mock('../src/utils/kubectl');

describe('Auto-Fix Utilities - Pod Operations', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('deletePod', () => {
    it('should successfully delete a pod', () => {
      kubectl.mockReturnValue('pod "test-pod" deleted');

      const result = deletePod('default', 'test-pod');

      expect(result.success).toBe(true);
      expect(result.output).toBe('pod "test-pod" deleted');
      expect(kubectl).toHaveBeenCalledWith(['delete', 'pod', 'test-pod', '-n', 'default']);
    });

    it('should handle pod deletion failure', () => {
      kubectl.mockImplementation(() => {
        throw new Error('pod not found');
      });

      const result = deletePod('default', 'missing-pod');

      expect(result.success).toBe(false);
      expect(result.error).toBeDefined();
      expect(result.error).toContain('pod not found');
    });

    it('should handle namespace with special characters', () => {
      kubectl.mockReturnValue('pod "test-pod" deleted');

      const result = deletePod('akash-services-123', 'test-pod');

      expect(result.success).toBe(true);
      expect(kubectl).toHaveBeenCalledWith(['delete', 'pod', 'test-pod', '-n', 'akash-services-123']);
    });
  });

  describe('restartDeployment', () => {
    it('should successfully restart a deployment using rollout restart', () => {
      kubectl.mockReturnValue('deployment "provider" restarted');

      const result = restartDeployment('default', 'provider');

      expect(result.success).toBe(true);
      expect(result.output).toBe('deployment "provider" restarted');
      expect(kubectl).toHaveBeenCalledWith(['rollout', 'restart', 'deployment', 'provider', '-n', 'default']);
    });

    it('should handle deployment restart failure', () => {
      kubectl.mockImplementation(() => {
        throw new Error('deployment not found');
      });

      const result = restartDeployment('default', 'missing-deployment');

      expect(result.success).toBe(false);
      expect(result.error).toBeDefined();
      expect(result.error).toContain('deployment not found');
    });

    it('should handle statefulset restart', () => {
      kubectl.mockReturnValue('statefulset "provider" restarted');

      const result = restartDeployment('default', 'provider', 'statefulset');

      expect(result.success).toBe(true);
      expect(kubectl).toHaveBeenCalledWith(['rollout', 'restart', 'statefulset', 'provider', '-n', 'default']);
    });
  });

  describe('scaleDeployment', () => {
    it('should successfully scale deployment up', () => {
      kubectl.mockReturnValue('deployment.provider scaled');

      const result = scaleDeployment('default', 'provider', 3);

      expect(result.success).toBe(true);
      expect(result.output).toBe('deployment.provider scaled');
      expect(kubectl).toHaveBeenCalledWith(['scale', 'deployment', 'provider', '--replicas=3', '-n', 'default']);
    });

    it('should successfully scale deployment down', () => {
      kubectl.mockReturnValue('deployment.provider scaled');

      const result = scaleDeployment('default', 'provider', 0);

      expect(result.success).toBe(true);
      expect(kubectl).toHaveBeenCalledWith(['scale', 'deployment', 'provider', '--replicas=0', '-n', 'default']);
    });

    it('should handle scale failure', () => {
      kubectl.mockImplementation(() => {
        throw new Error('invalid replica count');
      });

      const result = scaleDeployment('default', 'provider', -1);

      expect(result.success).toBe(false);
      expect(result.error).toBeDefined();
      expect(result.error).toContain('invalid replica count');
    });

    it('should handle statefulset scaling', () => {
      kubectl.mockReturnValue('statefulset.provider scaled');

      const result = scaleDeployment('default', 'provider', 2, 'statefulset');

      expect(result.success).toBe(true);
      expect(kubectl).toHaveBeenCalledWith(['scale', 'statefulset', 'provider', '--replicas=2', '-n', 'default']);
    });
  });

  describe('deletePods', () => {
    it('should successfully delete multiple pods by label selector', () => {
      kubectl.mockReturnValue('pod "miner-1" deleted\npod "miner-2" deleted\npod "miner-3" deleted');

      const result = deletePods('mining', 'app=gpu-miner');

      expect(result.success).toBe(true);
      expect(result.output).toContain('pod "miner-1" deleted');
      expect(result.output).toContain('pod "miner-2" deleted');
      expect(result.output).toContain('pod "miner-3" deleted');
      expect(kubectl).toHaveBeenCalledWith(['delete', 'pod', '-l', 'app=gpu-miner', '-n', 'mining']);
    });

    it('should handle no pods matching selector', () => {
      kubectl.mockReturnValue('No resources found');

      const result = deletePods('default', 'app=nonexistent');

      expect(result.success).toBe(true);
      expect(result.output).toBe('No resources found');
    });

    it('should handle deletion failure', () => {
      kubectl.mockImplementation(() => {
        throw new Error('invalid selector');
      });

      const result = deletePods('default', 'invalid==selector');

      expect(result.success).toBe(false);
      expect(result.error).toBeDefined();
      expect(result.error).toContain('invalid selector');
    });

    it('should handle complex label selectors', () => {
      kubectl.mockReturnValue('pod "test-abc123" deleted');

      const result = deletePods('default', 'app=gpu-miner,gpu-type=nvidia');

      expect(result.success).toBe(true);
      expect(kubectl).toHaveBeenCalledWith(['delete', 'pod', '-l', 'app=gpu-miner,gpu-type=nvidia', '-n', 'default']);
    });
  });
});

describe('Auto-Fix Coordinator - attemptAutoFix', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Automatic Fixes (autoFix=true)', () => {
    it('should execute pod-delete fix automatically', () => {
      const issue = {
        id: 'stuck-pod',
        severity: 'medium',
        fixAction: 'pod-delete',
        risk: 'low',
        autoFix: true
      };

      kubectl.mockReturnValue('pod "stuck-pod" deleted');

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'default',
        podName: 'stuck-pod'
      });

      expect(result.success).toBe(true);
      expect(result.action).toBe('pod-delete');
      expect(result.requiredPermission).toBe(false);
      expect(result.output).toContain('deleted');
    });

    it('should execute deployment restart fix automatically', () => {
      const issue = {
        id: 'deployment-crashloop',
        severity: 'high',
        fixAction: 'restart',
        risk: 'low',
        autoFix: true
      };

      kubectl.mockReturnValue('deployment "miner" restarted');

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'mining',
        deploymentName: 'miner'
      });

      expect(result.success).toBe(true);
      expect(result.action).toBe('restart');
      expect(result.requiredPermission).toBe(false);
    });

    it('should execute scale fix automatically', () => {
      const issue = {
        id: 'under-provisioned',
        severity: 'medium',
        fixAction: 'scale',
        risk: 'low',
        autoFix: true
      };

      kubectl.mockReturnValue('deployment.miner scaled');

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'mining',
        deploymentName: 'miner',
        replicas: 3
      });

      expect(result.success).toBe(true);
      expect(result.action).toBe('scale');
      expect(result.requiredPermission).toBe(false);
    });

    it('should require permission for provider-config changes even with autoFix=true', () => {
      const issue = {
        id: 'provider-attributes-missing',
        severity: 'high',
        fixAction: 'provider-config',
        risk: 'high',
        autoFix: false
      };

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'akash-services'
      });

      expect(result.success).toBe(false);
      expect(result.requiredPermission).toBe(true);
      expect(result.reason).toContain('high-risk');
    });

    it('should require permission for resource-delete even with autoFix=true', () => {
      const issue = {
        id: 'delete-deployment',
        severity: 'critical',
        fixAction: 'resource-delete',
        risk: 'high',
        autoFix: false
      };

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'default',
        resourceName: 'old-deployment'
      });

      expect(result.success).toBe(false);
      expect(result.requiredPermission).toBe(true);
      expect(result.reason).toContain('high-risk');
    });
  });

  describe('Permission-Required Fixes (autoFix=false)', () => {
    it('should require permission for pod-delete when autoFix=false', () => {
      const issue = {
        id: 'stuck-pod',
        severity: 'medium',
        fixAction: 'pod-delete',
        risk: 'low',
        autoFix: true
      };

      const result = attemptAutoFix(issue, {
        autoFix: false,
        namespace: 'default',
        podName: 'stuck-pod'
      });

      expect(result.success).toBe(false);
      expect(result.requiredPermission).toBe(true);
      expect(result.action).toBe('pod-delete');
      expect(result.reason).toContain('autoFix disabled');
    });

    it('should require permission for restart when autoFix=false', () => {
      const issue = {
        id: 'deployment-crashloop',
        severity: 'high',
        fixAction: 'restart',
        risk: 'low',
        autoFix: true
      };

      const result = attemptAutoFix(issue, {
        autoFix: false,
        namespace: 'mining',
        deploymentName: 'miner'
      });

      expect(result.success).toBe(false);
      expect(result.requiredPermission).toBe(true);
      expect(result.action).toBe('restart');
    });

    it('should always require permission for provider-config', () => {
      const issue = {
        id: 'provider-attributes-missing',
        severity: 'high',
        fixAction: 'provider-config',
        risk: 'high',
        autoFix: false
      };

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'akash-services'
      });

      expect(result.success).toBe(false);
      expect(result.requiredPermission).toBe(true);
      expect(result.reason).toContain('high-risk operation');
    });

    it('should always require permission for resource-delete', () => {
      const issue = {
        id: 'delete-deployment',
        severity: 'critical',
        fixAction: 'resource-delete',
        risk: 'high',
        autoFix: false
      };

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'default',
        resourceName: 'old-deployment'
      });

      expect(result.success).toBe(false);
      expect(result.requiredPermission).toBe(true);
      expect(result.reason).toContain('high-risk operation');
    });
  });

  describe('Edge Cases and Error Handling', () => {
    it('should handle unknown fix actions', () => {
      const issue = {
        id: 'unknown-fix',
        severity: 'low',
        fixAction: 'unknown-action',
        risk: 'low',
        autoFix: true
      };

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'default'
      });

      expect(result.success).toBe(false);
      expect(result.requiredPermission).toBe(true);
      expect(result.reason).toContain('Unknown fix action');
    });

    it('should handle fix execution failure', () => {
      const issue = {
        id: 'stuck-pod',
        severity: 'medium',
        fixAction: 'pod-delete',
        risk: 'low',
        autoFix: true
      };

      kubectl.mockImplementation(() => {
        throw new Error('pod not found');
      });

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'default',
        podName: 'missing-pod'
      });

      expect(result.success).toBe(false);
      expect(result.error).toBeDefined();
      expect(result.error).toContain('pod not found');
    });

    it('should handle missing required parameters', () => {
      const issue = {
        id: 'restart-missing-name',
        severity: 'high',
        fixAction: 'restart',
        risk: 'low',
        autoFix: true
      };

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'default'
        // Missing deploymentName
      });

      expect(result.success).toBe(false);
      expect(result.error).toBeDefined();
      expect(result.error).toContain('deploymentName');
    });

    it('should handle issue without fixAction', () => {
      const issue = {
        id: 'no-fix-available',
        severity: 'low',
        risk: 'low'
      };

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'default'
      });

      expect(result.success).toBe(false);
      expect(result.requiredPermission).toBe(true);
      expect(result.reason).toContain('No fix action available');
    });

    it('should handle missing autoFix flag (default to false)', () => {
      const issue = {
        id: 'no-autofix-flag',
        severity: 'medium',
        fixAction: 'pod-delete',
        risk: 'low'
      };

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'default',
        podName: 'test-pod'
      });

      expect(result.success).toBe(false);
      expect(result.requiredPermission).toBe(true);
      expect(result.reason).toContain('Issue not marked for automatic fixing');
    });
  });

  describe('Risk-Based Decision Making', () => {
    it('should allow low-risk automatic fixes', () => {
      const issue = {
        id: 'low-risk-fix',
        severity: 'low',
        fixAction: 'pod-delete',
        risk: 'low',
        autoFix: true
      };

      kubectl.mockReturnValue('pod deleted');

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'default',
        podName: 'test-pod'
      });

      expect(result.success).toBe(true);
      expect(result.requiredPermission).toBe(false);
    });

    it('should allow medium-risk automatic fixes', () => {
      const issue = {
        id: 'medium-risk-fix',
        severity: 'medium',
        fixAction: 'restart',
        risk: 'medium',
        autoFix: true
      };

      kubectl.mockReturnValue('deployment restarted');

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'default',
        deploymentName: 'test'
      });

      expect(result.success).toBe(true);
      expect(result.requiredPermission).toBe(false);
    });

    it('should require permission for high-risk operations', () => {
      const issue = {
        id: 'high-risk-fix',
        severity: 'high',
        fixAction: 'provider-config',
        risk: 'high',
        autoFix: false
      };

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'default'
      });

      expect(result.success).toBe(false);
      expect(result.requiredPermission).toBe(true);
      expect(result.reason).toContain('high-risk operation');
    });

    it('should require permission for critical-risk operations', () => {
      const issue = {
        id: 'critical-risk-fix',
        severity: 'critical',
        fixAction: 'resource-delete',
        risk: 'critical',
        autoFix: false
      };

      const result = attemptAutoFix(issue, {
        autoFix: true,
        namespace: 'default',
        resourceName: 'test-resource'
      });

      expect(result.success).toBe(false);
      expect(result.requiredPermission).toBe(true);
      expect(result.reason).toContain('high-risk operation');
    });
  });
});
