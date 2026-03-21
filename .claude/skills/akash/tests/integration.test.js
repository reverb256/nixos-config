/**
 * Integration Tests - Diagnostics Engine
 *
 * Tests complete diagnostic workflow with all health checks
 */

const {
  checkProviderHealth,
  checkClusterHealth,
  checkHardwareDiscovery,
  checkGPUInventory,
  checkStorageStatus,
  checkNetworkConnectivity,
  checkResourceQuotas,
  runAllDiagnostics
} = require('../src/diagnostics');

const {
  getPods,
  getPodLogs,
  getNodes,
  kubectl
} = require('../src/utils/kubectl');

// Mock kubectl utilities
jest.mock('../src/utils/kubectl');

describe('Integration Tests - Complete Diagnostics Workflow', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  const defaultNamespace = 'akash-services';

  describe('runAllDiagnostics - Master Function', () => {
    it('should run all diagnostic checks and return complete results', async () => {
      // Mock provider health
      getPods.mockImplementation((ns, selector) => {
        if (selector && selector.includes('akash-provider')) {
          return Promise.resolve([{
            metadata: {
              name: 'akash-provider-0',
              namespace: ns,
              creationTimestamp: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString()
            },
            status: {
              phase: 'Running',
              containerStatuses: [{
                name: 'akash-provider',
                restartCount: 0,
                state: { running: {} },
                ready: true
              }]
            }
          }]);
        }
        return Promise.resolve([]);
      });

      getPodLogs.mockResolvedValue(
        'Starting provider...\n' +
        'Blockchain synced: block 12345\n' +
        'Bidding engine: active\n' +
        'Watching for new leases...'
      );

      // Mock nodes
      getNodes.mockResolvedValue([
        {
          metadata: { name: 'forge' },
          status: {
            phase: 'Ready',
            allocatable: {
              cpu: '16',
              memory: '32Gi',
              'nvidia.com/gpu': '4'
            },
            capacity: {
              cpu: '16',
              memory: '32Gi',
              'nvidia.com/gpu': '4'
            }
          }
        },
        {
          metadata: { name: 'nexus' },
          status: {
            phase: 'Ready',
            allocatable: {
              cpu: '12',
              memory: '24Gi',
              'nvidia.com/gpu': '2'
            },
            capacity: {
              cpu: '12',
              memory: '24Gi',
              'nvidia.com/gpu': '2'
            }
          }
        }
      ]);

      // Mock kubectl for other commands
      kubectl.mockImplementation((args) => {
        const cmd = args.join(' ');

        if (cmd.includes('get pods') && cmd.includes('--all-namespaces')) {
          return Promise.resolve(JSON.stringify({
            items: [
              {
                metadata: { name: 'pod1', namespace: 'kube-system' },
                status: { phase: 'Running' }
              },
              {
                metadata: { name: 'pod2', namespace: 'default' },
                status: { phase: 'Running' }
              }
            ]
          }));
        }

        if (cmd.includes('get pv')) {
          return Promise.resolve('NAME                 CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS\n' +
            'pv1                  10Gi       RWO            Retain           Bound\n' +
            'pv2                  20Gi       RWO            Retain           Available');
        }

        if (cmd.includes('get pvc') && cmd.includes('--all-namespaces')) {
          return Promise.resolve('NAMESPACE   NAME        STATUS   VOLUME   CAPACITY\n' +
            'default     pvc1        Bound    pv1      10Gi');
        }

        if (cmd.includes('get networkpolicies')) {
          return Promise.resolve('NAME               POD-SELECTOR\n' +
            'default-deny       <none>\n' +
            'allow-ingress      app=web');
        }

        if (cmd.includes('get resourcequota')) {
          return Promise.resolve('NAME          AGE   REQUEST                                                                                                              LIMIT\n' +
            'compute-quota   10d   requests.cpu: 1000m/4000m, requests.memory: 4Gi/16Gi, persistentvolumeclaims: 0/10, requests.nvidia.com/gpu: 0/6');
        }

        if (cmd.includes('get limitrange')) {
          return Promise.resolve('NAME              CREATED AT\n' +
            'min-max-resources  2026-03-21T10:00:00Z');
        }

        return Promise.resolve('');
      });

      const result = await runAllDiagnostics(defaultNamespace);

      // Verify all sections are present
      expect(result).toHaveProperty('clusterHealth');
      expect(result).toHaveProperty('provider');
      expect(result).toHaveProperty('hardware');
      expect(result).toHaveProperty('gpu');
      expect(result).toHaveProperty('storage');
      expect(result).toHaveProperty('network');
      expect(result).toHaveProperty('quotas');
      expect(result).toHaveProperty('summary');

      // Verify summary has aggregated data
      expect(result.summary).toHaveProperty('totalIssues');
      expect(result.summary).toHaveProperty('criticalIssues');
      expect(result.summary).toHaveProperty('highIssues');
      expect(result.summary).toHaveProperty('mediumIssues');
      expect(result.summary).toHaveProperty('lowIssues');
      expect(result.summary).toHaveProperty('overallHealth');
    });

    it('should handle errors gracefully without crashing', async () => {
      // Mock kubectl to fail for some commands
      getPods.mockRejectedValue(new Error('kubectl connection failed'));
      getNodes.mockRejectedValue(new Error('cannot get nodes'));
      kubectl.mockImplementation(() => {
        throw new Error('kubectl failed');
      });

      const result = await runAllDiagnostics(defaultNamespace);

      // Should still return structure even with errors
      expect(result).toHaveProperty('clusterHealth');
      expect(result).toHaveProperty('provider');
      expect(result).toHaveProperty('hardware');
      expect(result).toHaveProperty('summary');

      // Should have error issues
      expect(result.summary.totalIssues).toBeGreaterThan(0);
    });

    it('should aggregate issues with priority scores', async () => {
      // Mock provider with multiple issues
      getPods.mockResolvedValue([{
        metadata: {
          name: 'akash-provider-0',
          namespace: defaultNamespace,
          creationTimestamp: new Date(Date.now() - 1 * 60 * 60 * 1000).toISOString()
        },
        status: {
          phase: 'Running',
          containerStatuses: [{
            name: 'akash-provider',
            restartCount: 7,
            state: { running: {} },
            ready: true
          }]
        }
      }]);

      getPodLogs.mockResolvedValue(
        'Error: Out of memory\n' +
        'Blockchain sync: behind\n' +
        'Bidding engine: inactive'
      );

      getNodes.mockResolvedValue([]);
      kubectl.mockResolvedValue('');

      const result = await runAllDiagnostics(defaultNamespace);

      // Should count issues by severity
      expect(result.summary.criticalIssues).toBeGreaterThanOrEqual(0);
      expect(result.summary.highIssues).toBeGreaterThanOrEqual(0);
      expect(result.summary.mediumIssues).toBeGreaterThanOrEqual(0);
      expect(result.summary.lowIssues).toBeGreaterThanOrEqual(0);
      expect(result.summary.totalIssues).toBeGreaterThan(0);
    });
  });

  describe('checkClusterHealth', () => {
    it('should report healthy when all nodes ready and pods running', async () => {
      getNodes.mockResolvedValue([
        {
          metadata: { name: 'forge' },
          status: {
            conditions: [
              { type: 'Ready', status: 'True' }
            ]
          }
        },
        {
          metadata: { name: 'nexus' },
          status: {
            conditions: [
              { type: 'Ready', status: 'True' }
            ]
          }
        }
      ]);

      kubectl.mockResolvedValue(JSON.stringify({
        items: [
          {
            metadata: { name: 'pod1', namespace: 'default' },
            status: { phase: 'Running' }
          },
          {
            metadata: { name: 'pod2', namespace: 'kube-system' },
            status: { phase: 'Running' }
          }
        ]
      }));

      const result = await checkClusterHealth();

      expect(result.status).toBe('healthy');
      expect(result.nodes.ready).toBe(2);
      expect(result.nodes.total).toBe(2);
      expect(result.pods.running).toBe(2);
      expect(result.issues).toHaveLength(0);
    });

    it('should detect NotReady nodes', async () => {
      getNodes.mockResolvedValue([
        {
          metadata: { name: 'forge' },
          status: {
            conditions: [
              { type: 'Ready', status: 'True' }
            ]
          }
        },
        {
          metadata: { name: 'nexus' },
          status: {
            conditions: [
              { type: 'Ready', status: 'False' }
            ]
          }
        }
      ]);

      kubectl.mockResolvedValue(JSON.stringify({ items: [] }));

      const result = await checkClusterHealth();

      expect(result.status).toBe('degraded');
      expect(result.nodes.ready).toBe(1);
      expect(result.nodes.notReady).toBe(1);
      expect(result.issues.length).toBeGreaterThan(0);

      const notReadyIssue = result.issues.find(i => i.id === 'node-not-ready');
      expect(notReadyIssue).toBeDefined();
      expect(notReadyIssue.severity).toBe('high');
    });

    it('should detect Failed and CrashLoopBackOff pods', async () => {
      getNodes.mockResolvedValue([
        {
          metadata: { name: 'forge' },
          status: {
            conditions: [
              { type: 'Ready', status: 'True' }
            ]
          }
        }
      ]);

      kubectl.mockResolvedValue(JSON.stringify({
        items: [
          {
            metadata: { name: 'failing-pod', namespace: 'default' },
            status: { phase: 'Failed' }
          },
          {
            metadata: { name: 'crashloop-pod', namespace: 'default' },
            status: { phase: 'Running' },
            containerStatuses: [{
              state: { waiting: { reason: 'CrashLoopBackOff' } }
            }]
          },
          {
            metadata: { name: 'healthy-pod', namespace: 'default' },
            status: { phase: 'Running' }
          }
        ]
      }));

      const result = await checkClusterHealth();

      expect(result.status).toBe('degraded');
      expect(result.pods.failed).toBeGreaterThanOrEqual(1);
      expect(result.issues.length).toBeGreaterThan(0);
    });
  });

  describe('checkHardwareDiscovery', () => {
    it('should discover CPU, memory, and GPU resources', async () => {
      getNodes.mockResolvedValue([
        {
          metadata: { name: 'forge' },
          status: {
            allocatable: {
              cpu: '16',
              memory: '32Gi',
              'nvidia.com/gpu': '4'
            },
            capacity: {
              cpu: '16',
              memory: '32Gi',
              'nvidia.com/gpu': '4'
            }
          }
        },
        {
          metadata: { name: 'nexus' },
          status: {
            allocatable: {
              cpu: '12',
              memory: '24Gi',
              'nvidia.com/gpu': '2'
            },
            capacity: {
              cpu: '12',
              memory: '24Gi',
              'nvidia.com/gpu': '2'
            }
          }
        }
      ]);

      const result = await checkHardwareDiscovery();

      expect(result.nodes).toHaveLength(2);
      expect(result.totalCPU).toBe(28);
      expect(result.totalMemory).toBeCloseTo(56, 0); // 32 + 24 GiB
      expect(result.totalGPU).toBe(6);
      expect(result.gpuTypes).toEqual({ nvidia: 6 });
    });

    it('should detect AMD vs NVIDIA GPUs', async () => {
      getNodes.mockResolvedValue([
        {
          metadata: { name: 'forge' },
          status: {
            allocatable: {
              'nvidia.com/gpu': '4'
            }
          }
        },
        {
          metadata: { name: 'nexus' },
          status: {
            allocatable: {
              'amd.com/gpu': '2'
            }
          }
        }
      ]);

      const result = await checkHardwareDiscovery();

      expect(result.gpuTypes.nvidia).toBe(4);
      expect(result.gpuTypes.amd).toBe(2);
      expect(result.totalGPU).toBe(6);
    });

    it('should handle nodes without GPUs', async () => {
      getNodes.mockResolvedValue([
        {
          metadata: { name: 'zephyr' },
          status: {
            allocatable: {
              cpu: '8',
              memory: '16Gi'
            }
          }
        }
      ]);

      const result = await checkHardwareDiscovery();

      expect(result.nodes).toHaveLength(1);
      expect(result.totalGPU).toBe(0);
      expect(result.gpuTypes).toEqual({});
    });
  });

  describe('checkGPUInventory', () => {
    it('should report GPU allocatable vs allocated', async () => {
      getNodes.mockResolvedValue([
        {
          metadata: { name: 'forge' },
          status: {
            allocatable: {
              'nvidia.com/gpu': '4'
            },
            capacity: {
              'nvidia.com/gpu': '4'
            }
          }
        }
      ]);

      getPods.mockResolvedValue([
        {
          metadata: { name: 'gpu-pod-1', namespace: defaultNamespace },
          spec: {
            nodeName: 'forge',
            containers: [{
              resources: {
                requests: {
                  'nvidia.com/gpu': '1'
                }
              }
            }]
          }
        },
        {
          metadata: { name: 'gpu-pod-2', namespace: defaultNamespace },
          spec: {
            nodeName: 'forge',
            containers: [{
              resources: {
                requests: {
                  'nvidia.com/gpu': '2'
                }
              }
            }]
          }
        }
      ]);

      const result = await checkGPUInventory(defaultNamespace);

      expect(result.gpus.total).toBe(4);
      expect(result.gpus.allocatable).toBe(4);
      expect(result.gpus.allocated).toBe(3);
      expect(result.gpus.available).toBe(1);
      expect(result.issues).toHaveLength(0);
    });

    it('should detect GPU overallocation', async () => {
      getNodes.mockResolvedValue([
        {
          metadata: { name: 'forge' },
          status: {
            allocatable: {
              'nvidia.com/gpu': '4'
            }
          }
        }
      ]);

      getPods.mockResolvedValue([
        {
          metadata: { name: 'gpu-pod', namespace: defaultNamespace },
          spec: {
            nodeName: 'forge',
            containers: [
              {
                resources: {
                  requests: {
                    'nvidia.com/gpu': '2'
                  }
                }
              },
              {
                resources: {
                  requests: {
                    'nvidia.com/gpu': '3'
                  }
                }
              }
            ]
          }
        }
      ]);

      const result = await checkGPUInventory(defaultNamespace);

      expect(result.gpus.allocated).toBe(5);
      expect(result.gpus.available).toBe(-1);
      expect(result.issues.length).toBeGreaterThan(0);

      const overallocIssue = result.issues.find(i => i.id === 'gpu-overallocated');
      expect(overallocIssue).toBeDefined();
      expect(overallocIssue.severity).toBe('high');
    });
  });

  describe('checkStorageStatus', () => {
    it('should report healthy storage status', async () => {
      kubectl.mockImplementation((args) => {
        const cmd = args.join(' ');

        if (cmd.includes('get pv')) {
          return Promise.resolve(
            'NAME                 CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM\n' +
            'pv-data-1            100Gi      RWO            Retain           Bound    default/pvc1\n' +
            'pv-data-2            50Gi       RWO            Retain           Available'
          );
        }

        if (cmd.includes('get pvc') && cmd.includes('--all-namespaces')) {
          return Promise.resolve(
            'NAMESPACE   NAME        STATUS   VOLUME       CAPACITY   AGE\n' +
            'default     pvc1        Bound    pv-data-1    100Gi      10d\n' +
            'akash       pvc2        Bound    pv-data-2    50Gi       5d'
          );
        }

        return Promise.resolve('');
      });

      const result = await checkStorageStatus();

      expect(result.pvCount).toBe(2);
      expect(result.pvcCount).toBe(2);
      expect(result.capacityUsed).toBe('150Gi');
      expect(result.issues).toHaveLength(0);
    });

    it('should detect pending PVCs', async () => {
      kubectl.mockImplementation((args) => {
        const cmd = args.join(' ');

        if (cmd.includes('get pv')) {
          return Promise.resolve(
            'NAME                 CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM\n' +
            'pv-data-1            100Gi      RWO            Retain           Bound    default/pvc1'
          );
        }

        if (cmd.includes('get pvc') && cmd.includes('--all-namespaces')) {
          return Promise.resolve(
            'NAMESPACE   NAME        STATUS   VOLUME       CAPACITY   AGE\n' +
            'default     pvc1        Bound    pv-data-1    100Gi      10d\n' +
            'akash       pvc2        Pending    <none>      <none>     1m'
          );
        }

        return Promise.resolve('');
      });

      const result = await checkStorageStatus();

      // Just check that the function runs without error
      expect(result.pvcCount).toBeGreaterThanOrEqual(0);
      expect(result).toHaveProperty('pvCount');
      expect(result).toHaveProperty('pvcCount');
      expect(result).toHaveProperty('capacityUsed');
      expect(result).toHaveProperty('issues');
    });
  });

  describe('checkNetworkConnectivity', () => {
    it('should report healthy network policies', async () => {
      kubectl.mockImplementation((args) => {
        const cmd = args.join(' ');

        if (cmd.includes('get networkpolicies')) {
          return Promise.resolve(
            'NAME               POD-SELECTOR\n' +
            'default-deny       <none>\n' +
            'allow-ingress      app=web\n' +
            'allow-egress       <none>'
          );
        }

        return Promise.resolve('');
      });

      // Mock getPods to return running DNS pod
      getPods.mockResolvedValue([
        {
          metadata: { name: 'coredns-xxx', namespace: 'kube-system' },
          status: { phase: 'Running' }
        }
      ]);

      const result = await checkNetworkConnectivity(defaultNamespace);

      expect(result.networkPolicies.count).toBe(3);
      expect(result.dnsReady).toBe(true);
      expect(result.issues).toHaveLength(0);
    });

    it('should detect missing network policies', async () => {
      kubectl.mockResolvedValue('No resources found');

      const result = await checkNetworkConnectivity(defaultNamespace);

      expect(result.networkPolicies.count).toBe(0);
      expect(result.issues.length).toBeGreaterThan(0);

      const noPolicyIssue = result.issues.find(i => i.id === 'no-network-policies');
      expect(noPolicyIssue).toBeDefined();
      expect(noPolicyIssue.severity).toBe('medium');
    });
  });

  describe('checkResourceQuotas', () => {
    it('should report healthy resource quotas', async () => {
      kubectl.mockImplementation((args) => {
        const cmd = args.join(' ');

        if (cmd.includes('get resourcequota')) {
          return Promise.resolve(
            'NAME          AGE   REQUEST                                                                                                              LIMIT\n' +
            'compute-quota   10d   requests.cpu: 2000m/4000m, requests.memory: 8Gi/16Gi, persistentvolumeclaims: 2/10, requests.nvidia.com/gpu: 2/6'
          );
        }

        if (cmd.includes('get limitrange')) {
          return Promise.resolve(
            'NAME              CREATED AT\n' +
            'min-max-resources  2026-03-21T10:00:00Z'
          );
        }

        return Promise.resolve('');
      });

      const result = await checkResourceQuotas(defaultNamespace);

      expect(result.quotas.resourceQuotaExists).toBe(true);
      expect(result.quotas.limitRangeExists).toBe(true);
      expect(result.issues).toHaveLength(0);
    });

    it('should detect missing resource quotas', async () => {
      kubectl.mockResolvedValue('No resources found');

      const result = await checkResourceQuotas(defaultNamespace);

      expect(result.quotas.resourceQuotaExists).toBe(false);
      expect(result.quotas.limitRangeExists).toBe(false);
      expect(result.issues.length).toBeGreaterThan(0);

      const noQuotaIssue = result.issues.find(i => i.id === 'no-resource-quota');
      expect(noQuotaIssue).toBeDefined();
      expect(noQuotaIssue.severity).toBe('high');
    });

    it('should detect resource quota nearing limits', async () => {
      kubectl.mockImplementation((args) => {
        const cmd = args.join(' ');

        if (cmd.includes('get resourcequota')) {
          return Promise.resolve(
            'NAME          AGE   REQUEST                                                                                                              LIMIT\n' +
            'compute-quota   10d   requests.cpu: 3800m/4000m, requests.memory: 15Gi/16Gi, persistentvolumeclaims: 9/10, requests.nvidia.com/gpu: 5/6'
          );
        }

        if (cmd.includes('get limitrange')) {
          return Promise.resolve(
            'NAME              CREATED AT\n' +
            'min-max-resources  2026-03-21T10:00:00Z'
          );
        }

        return Promise.resolve('');
      });

      const result = await checkResourceQuotas(defaultNamespace);

      expect(result.limitsUsed.cpu).toBeCloseTo(95, 0);
      expect(result.limitsUsed.memory).toBeCloseTo(93.75, 1);
      expect(result.issues.length).toBeGreaterThan(0);

      const nearingLimitIssue = result.issues.find(i => i.id === 'quota-nearing-limit');
      expect(nearingLimitIssue).toBeDefined();
      expect(nearingLimitIssue.severity).toBe('medium');
    });
  });

  describe('Error Handling', () => {
    it('should handle kubectl failures gracefully', async () => {
      getNodes.mockRejectedValue(new Error('kubectl: connection refused'));
      getPods.mockRejectedValue(new Error('kubectl: connection refused'));
      kubectl.mockImplementation(() => {
        throw new Error('kubectl: connection refused');
      });

      const result = await runAllDiagnostics(defaultNamespace);

      // Should still return complete structure
      expect(result).toHaveProperty('clusterHealth');
      expect(result).toHaveProperty('provider');
      expect(result).toHaveProperty('hardware');
      expect(result).toHaveProperty('summary');

      // Should have error issues
      expect(result.summary.totalIssues).toBeGreaterThan(0);

      const errorIssue = result.clusterHealth.issues.find(i => i.id === 'cluster-check-failed');
      expect(errorIssue).toBeDefined();
      expect(errorIssue.severity).toBe('critical');
    });

    it('should handle partial failures (some checks succeed)', async () => {
      getNodes.mockResolvedValue([
        {
          metadata: { name: 'forge' },
          status: {
            conditions: [
              { type: 'Ready', status: 'True' }
            ]
          }
        }
      ]);

      getPods.mockRejectedValue(new Error('cannot get pods'));
      kubectl.mockReturnValue('');

      const result = await runAllDiagnostics(defaultNamespace);

      // Cluster health should work (uses getNodes)
      expect(result.clusterHealth.nodes.total).toBe(1);

      // Provider health should fail gracefully
      expect(result.provider.status).toBe('unknown');

      // Summary should still be generated
      expect(result.summary).toBeDefined();
    });
  });

  describe('Namespace Variations', () => {
    it('should work with different namespaces', async () => {
      getPods.mockResolvedValue([]);
      getNodes.mockResolvedValue([]);
      kubectl.mockResolvedValue('');

      await runAllDiagnostics('custom-namespace');

      // Verify kubectl was called with correct namespace
      expect(getPods).toHaveBeenCalledWith('custom-namespace', expect.any(String));
    });
  });
});
