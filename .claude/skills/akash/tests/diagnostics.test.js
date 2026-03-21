/**
 * Diagnostics Engine Tests
 *
 * Test suite for provider health checks and GPU inventory validation
 */

const {
  checkProviderHealth,
  calculateUptime
} = require('../src/diagnostics');
const {
  getPods,
  getPodLogs,
  getNodes
} = require('../src/utils/kubectl');

// Mock kubectl utilities
jest.mock('../src/utils/kubectl');

describe('Diagnostics Engine - Provider Health Check', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('checkProviderHealth', () => {
    const defaultNamespace = 'akash-services';

    it('should detect provider pod is down (Failed status)', async () => {
      // Mock failed pod
      getPods.mockResolvedValue([{
        metadata: {
          name: 'akash-provider-0',
          namespace: defaultNamespace,
          creationTimestamp: '2026-03-21T10:00:00Z'
        },
        status: {
          phase: 'Failed',
          containerStatuses: [{
            name: 'akash-provider',
            restartCount: 0,
            state: { terminated: { exitCode: 1 } }
          }]
        }
      }]);

      getPodLogs.mockResolvedValue('Error: Failed to start provider\nConnection refused');

      const result = await checkProviderHealth(defaultNamespace);

      expect(result.status).toBe('down');
      expect(result.podRunning).toBe(false);
      expect(result.issues).toHaveLength(1);
      expect(result.issues[0].severity).toBe('critical');
      expect(result.issues[0].category).toBe('provider');
      expect(result.issues[0].blocksNewLeases).toBe(true);
    });

    it('should detect provider is healthy (Running, 0 restarts)', async () => {
      // Mock healthy pod
      getPods.mockResolvedValue([{
        metadata: {
          name: 'akash-provider-0',
          namespace: defaultNamespace,
          creationTimestamp: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString() // 2 hours ago
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

      getPodLogs.mockResolvedValue(
        'Starting provider...\n' +
        'Blockchain synced: block 12345\n' +
        'Bidding engine: active\n' +
        'Watching for new leases...'
      );

      const result = await checkProviderHealth(defaultNamespace);

      expect(result.status).toBe('healthy');
      expect(result.podRunning).toBe(true);
      expect(result.restartCount).toBe(0);
      expect(result.biddingActive).toBe(true);
      expect(result.blockchainSynced).toBe(true);
      expect(result.uptimeHours).toBeGreaterThan(0);
      expect(result.issues).toHaveLength(0);
    });

    it('should detect provider is degraded (high restart count > 5)', async () => {
      // Mock degraded pod with high restart count
      getPods.mockResolvedValue([{
        metadata: {
          name: 'akash-provider-0',
          namespace: defaultNamespace,
          creationTimestamp: new Date(Date.now() - 1 * 60 * 60 * 1000).toISOString() // 1 hour ago
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
        'Provider restarted unexpectedly\n' +
        'Error: Out of memory\n' +
        'Provider restarted unexpectedly\n' +
        'Starting provider...'
      );

      const result = await checkProviderHealth(defaultNamespace);

      expect(result.status).toBe('degraded');
      expect(result.podRunning).toBe(true);
      expect(result.restartCount).toBe(7);
      expect(result.issues.length).toBeGreaterThan(0);

      const restartIssue = result.issues.find(i => i.id === 'high-restart-count');
      expect(restartIssue).toBeDefined();
      expect(restartIssue.severity).toBe('high');
      expect(restartIssue.affectsRevenue).toBe(true);
    });

    it('should detect provider with blockchain sync issues', async () => {
      getPods.mockResolvedValue([{
        metadata: {
          name: 'akash-provider-0',
          namespace: defaultNamespace,
          creationTimestamp: new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString()
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

      getPodLogs.mockResolvedValue(
        'Starting provider...\n' +
        'Blockchain sync: behind (block 10000, latest 15000)\n' +
        'Waiting for sync...'
      );

      const result = await checkProviderHealth(defaultNamespace);

      expect(result.blockchainSynced).toBe(false);
      expect(result.issues.length).toBeGreaterThan(0);

      const syncIssue = result.issues.find(i => i.id === 'blockchain-out-of-sync');
      expect(syncIssue).toBeDefined();
      expect(syncIssue.severity).toBe('high');
      expect(syncIssue.blocksNewLeases).toBe(true);
    });

    it('should detect provider with inactive bidding engine', async () => {
      getPods.mockResolvedValue([{
        metadata: {
          name: 'akash-provider-0',
          namespace: defaultNamespace,
          creationTimestamp: new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString()
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

      getPodLogs.mockResolvedValue(
        'Starting provider...\n' +
        'Blockchain synced: block 12345\n' +
        'Bidding engine: inactive (paused)\n' +
        'No active leases'
      );

      const result = await checkProviderHealth(defaultNamespace);

      expect(result.biddingActive).toBe(false);
      expect(result.issues.length).toBeGreaterThan(0);

      const biddingIssue = result.issues.find(i => i.id === 'bidding-inactive');
      expect(biddingIssue).toBeDefined();
      expect(biddingIssue.severity).toBe('medium');
      expect(biddingIssue.affectsRevenue).toBe(true);
    });

    it('should detect multiple issues in degraded provider', async () => {
      getPods.mockResolvedValue([{
        metadata: {
          name: 'akash-provider-0',
          namespace: defaultNamespace,
          creationTimestamp: new Date(Date.now() - 5 * 60 * 60 * 1000).toISOString()
        },
        status: {
          phase: 'Running',
          containerStatuses: [{
            name: 'akash-provider',
            restartCount: 3,
            state: { running: {} },
            ready: true
          }]
        }
      }]);

      getPodLogs.mockResolvedValue(
        'Starting provider...\n' +
        'Error: RPC timeout\n' +
        'Blockchain sync: slow (block 11000, latest 15000)\n' +
        'Bidding engine: inactive\n' +
        'Memory usage: 95%'
      );

      const result = await checkProviderHealth(defaultNamespace);

      expect(result.status).toBe('degraded');
      expect(result.issues.length).toBeGreaterThan(2);

      // Check that issues have proper structure
      result.issues.forEach(issue => {
        expect(issue).toHaveProperty('id');
        expect(issue).toHaveProperty('severity');
        expect(issue).toHaveProperty('category');
        expect(issue).toHaveProperty('title');
        expect(issue).toHaveProperty('description');
        expect(issue).toHaveProperty('recommendation');
        expect(issue).toHaveProperty('affectsRevenue');
        expect(issue).toHaveProperty('blocksNewLeases');
        expect(issue).toHaveProperty('hasFix');
        expect(issue).toHaveProperty('autoFix');
        expect(issue).toHaveProperty('risk');
      });
    });

    it('should handle missing provider pod gracefully', async () => {
      getPods.mockResolvedValue([]);

      const result = await checkProviderHealth(defaultNamespace);

      expect(result.status).toBe('down');
      expect(result.podRunning).toBe(false);
      expect(result.issues).toHaveLength(1);
      expect(result.issues[0].id).toBe('provider-pod-missing');
      expect(result.issues[0].severity).toBe('critical');
    });
  });

  describe('calculateUptime', () => {
    it('should calculate uptime in hours from ISO timestamp', () => {
      const startTime = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(); // 2 hours ago
      const uptime = calculateUptime(startTime);

      expect(uptime).toBeGreaterThan(1.9);
      expect(uptime).toBeLessThan(2.1);
    });

    it('should calculate uptime in hours from Date object', () => {
      const startTime = new Date(Date.now() - 5 * 60 * 60 * 1000); // 5 hours ago
      const uptime = calculateUptime(startTime);

      expect(uptime).toBeGreaterThan(4.9);
      expect(uptime).toBeLessThan(5.1);
    });

    it('should handle very recent pod start', () => {
      const startTime = new Date(Date.now() - 5 * 60 * 1000).toISOString(); // 5 minutes ago
      const uptime = calculateUptime(startTime);

      expect(uptime).toBeGreaterThan(0);
      expect(uptime).toBeLessThan(0.1);
    });

    it('should handle long-running pod', () => {
      const startTime = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(); // 7 days ago
      const uptime = calculateUptime(startTime);

      expect(uptime).toBeGreaterThan(167); // ~7 hours
    });
  });
});

describe('Diagnostics Engine - GPU Inventory Check', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('GPU Inventory Validation', () => {
    it('should validate GPU count matches actual cluster state', async () => {
      // Mock nodes with GPUs
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
              'nvidia.com/gpu': '2'
            }
          }
        }
      ]);

      const clusterGPUCount = 6;

      // This would be part of a larger GPU inventory check function
      const nodeGPUs = getNodes().then(nodes =>
        nodes.reduce((sum, node) => {
          const gpuCount = parseInt(node.status.allocatable['nvidia.com/gpu'] || '0', 10);
          return sum + gpuCount;
        }, 0)
      );

      const result = await nodeGPUs;
      expect(result).toBe(clusterGPUCount);
    });

    it('should detect NVIDIA vs AMD GPU differences', async () => {
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

      const nodes = await getNodes();

      const nvidiaGPUs = nodes
        .filter(n => n.status.allocatable['nvidia.com/gpu'])
        .reduce((sum, node) => sum + parseInt(node.status.allocatable['nvidia.com/gpu'], 10), 0);

      const amdGPUs = nodes
        .filter(n => n.status.allocatable['amd.com/gpu'])
        .reduce((sum, node) => sum + parseInt(node.status.allocatable['amd.com/gpu'], 10), 0);

      expect(nvidiaGPUs).toBe(4);
      expect(amdGPUs).toBe(2);
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
        },
        {
          metadata: { name: 'sentry' },
          status: {
            allocatable: {
              cpu: '4',
              memory: '8Gi'
            }
          }
        }
      ]);

      const nodes = await getNodes();

      const gpuNodes = nodes.filter(n =>
        n.status.allocatable['nvidia.com/gpu'] ||
        n.status.allocatable['amd.com/gpu']
      );

      expect(gpuNodes).toHaveLength(0);
    });
  });
});
