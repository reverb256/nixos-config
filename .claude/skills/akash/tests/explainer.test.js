/**
 * Tests for explanation generator
 * Implements Task 4: Explanation Generator
 */

const {
  generateReport,
  generateTopology,
  explainTopic,
  getRelatedTopics
} = require('../src/explainer');

describe('Explanation Generator - Report Generation', () => {
  it('should generate markdown report from audit results', () => {
    const clusterState = {
      provider: {
        attributes: {
          'host': 'akash.network',
          'capabilities': 'compute,storage'
        },
        hostUri: 'https://provider.akash.network'
      },
      nodes: [
        {
          name: 'forge',
          ready: true,
          gpus: {
            total: 4,
            used: 3,
            free: 1,
            allocation: [
              { id: 'nvidia-0', model: 'RTX 3080', used: true, leaseId: 'lease1' },
              { id: 'nvidia-1', model: 'RTX 3080', used: true, leaseId: 'lease2' },
              { id: 'nvidia-2', model: 'RTX 3080', used: true, leaseId: 'lease3' },
              { id: 'nvidia-3', model: 'RTX 3080', used: false, leaseId: null }
            ]
          }
        },
        {
          name: 'nexus',
          ready: true,
          gpus: {
            total: 2,
            used: 0,
            free: 2,
            allocation: [
              { id: 'amd-0', model: 'RX 6800', used: false, leaseId: null },
              { id: 'amd-1', model: 'RX 6800', used: false, leaseId: null }
            ]
          }
        }
      ],
      leases: [
        { dseq: '123', owner: 'tenant1', state: 'active' }
      ]
    };

    const issues = [
      {
        severity: 'warning',
        node: 'forge',
        message: 'High GPU utilization (75%)',
        details: 'Consider scaling workload'
      },
      {
        severity: 'info',
        node: 'nexus',
        message: 'Node fully available',
        details: 'Ready for new leases'
      }
    ];

    const recommendations = [
      'Monitor GPU temperatures on forge',
      'Consider load balancing across nodes'
    ];

    const metadata = {
      duration: 2345,
      command: 'audit'
    };

    const report = generateReport(clusterState, issues, recommendations, null, metadata);

    expect(report).toBeDefined();
    expect(typeof report).toBe('string');
    expect(report).toContain('# Akash Provider Audit Report');
    expect(report).toContain('**Duration:**');
    expect(report).toContain('**Generated:**');
  });

  it('should include required sections in report', () => {
    const clusterState = {
      provider: { attributes: {}, hostUri: '' },
      nodes: [],
      leases: []
    };

    const report = generateReport(clusterState, [], [], null, { duration: 1000, command: 'audit' });

    // Check for required sections
    expect(report).toContain('## Executive Summary');
    expect(report).toContain('## Issues Found');
    expect(report).toContain('## Recommendations');
  });

  it('should use proper emoji indicators', () => {
    const clusterState = {
      provider: { attributes: {}, hostUri: '' },
      nodes: [
        { name: 'test', ready: true, gpus: { total: 1, used: 0, free: 1 } }
      ],
      leases: []
    };

    const issues = [
      { severity: 'warning', node: 'test', message: 'Test warning' },
      { severity: 'error', node: 'test', message: 'Test error' }
    ];

    const report = generateReport(clusterState, issues, [], null, { duration: 1000, command: 'audit' });

    // Should show warning and critical emojis for issues
    expect(report).toContain('⚠️');
    expect(report).toContain('🔴');
  });

  it('should include cluster topology if provided', () => {
    const clusterState = {
      provider: { attributes: {}, hostUri: '' },
      nodes: [],
      leases: []
    };

    const topology = '┌─ forge ─┐\n│ GPU: 4  │\n└─────────┘';

    const report = generateReport(clusterState, [], [], topology, { duration: 1000, command: 'audit' });

    expect(report).toContain('## Cluster Topology');
    expect(report).toContain('┌─ forge ─┐');
  });

  it('should categorize issues by severity', () => {
    const clusterState = {
      provider: { attributes: {}, hostUri: '' },
      nodes: [],
      leases: []
    };

    const issues = [
      { severity: 'error', node: 'test', message: 'Critical issue' },
      { severity: 'warning', node: 'test', message: 'Warning issue' },
      { severity: 'info', node: 'test', message: 'Info issue' }
    ];

    const report = generateReport(clusterState, issues, [], null, { duration: 1000, command: 'audit' });

    // Should have sections for each severity
    expect(report).toContain('### Critical');
    expect(report).toContain('### Warnings');
    expect(report).toContain('### Informational');
  });

  it('should handle empty issues array', () => {
    const clusterState = {
      provider: { attributes: {}, hostUri: '' },
      nodes: [
        { name: 'test', ready: true, gpus: { total: 1, used: 0, free: 1 } }
      ],
      leases: []
    };

    const report = generateReport(clusterState, [], [], null, { duration: 1000, command: 'audit' });

    expect(report).toContain('No issues detected');
  });
});

describe('Explanation Generator - ASCII Topology', () => {
  it('should generate topology diagram with all nodes', () => {
    const clusterState = {
      nodes: [
        { name: 'forge', ready: true, gpus: { total: 4, used: 3, free: 1 } },
        { name: 'nexus', ready: true, gpus: { total: 2, used: 0, free: 2 } },
        { name: 'sentry', ready: true, gpus: { total: 0, used: 0, free: 0 } },
        { name: 'zephyr', ready: true, gpus: { total: 1, used: 1, free: 0 } }
      ]
    };

    const topology = generateTopology(clusterState);

    expect(topology).toContain('forge');
    expect(topology).toContain('nexus');
    expect(topology).toContain('sentry');
    expect(topology).toContain('zephyr');
  });

  it('should render GPU bars correctly', () => {
    const clusterState = {
      nodes: [
        {
          name: 'forge',
          ready: true,
          gpus: {
            total: 4,
            used: 3,
            free: 1,
            allocation: [
              { id: 'nvidia-0', used: true },
              { id: 'nvidia-1', used: true },
              { id: 'nvidia-2', used: true },
              { id: 'nvidia-3', used: false }
            ]
          }
        }
      ]
    };

    const topology = generateTopology(clusterState);

    // Should show used (██) and free (░░) indicators
    expect(topology).toContain('██');
    expect(topology).toContain('░░');
  });

  it('should display correct GPU counts', () => {
    const clusterState = {
      nodes: [
        {
          name: 'forge',
          ready: true,
          gpus: { total: 4, used: 3, free: 1 }
        }
      ]
    };

    const topology = generateTopology(clusterState);

    expect(topology).toContain('Total: 4');
    expect(topology).toContain('Used: 3');
    expect(topology).toContain('Free: 1');
  });

  it('should use box-drawing characters', () => {
    const clusterState = {
      nodes: [
        { name: 'test', ready: true, gpus: { total: 1, used: 0, free: 1 } }
      ]
    };

    const topology = generateTopology(clusterState);

    expect(topology).toContain('┌');
    expect(topology).toContain('─');
    expect(topology).toContain('│');
    expect(topology).toContain('└');
    expect(topology).toContain('┐');
  });

  it('should show node readiness status', () => {
    const clusterState = {
      nodes: [
        { name: 'ready-node', ready: true, gpus: { total: 1, used: 0, free: 1 } },
        { name: 'not-ready-node', ready: false, gpus: { total: 1, used: 0, free: 1 } }
      ]
    };

    const topology = generateTopology(clusterState);

    expect(topology).toContain('✅');
    expect(topology).toContain('🔴');
  });

  it('should handle nodes with no GPUs', () => {
    const clusterState = {
      nodes: [
        { name: 'sentry', ready: true, gpus: { total: 0, used: 0, free: 0 } }
      ]
    };

    const topology = generateTopology(clusterState);

    expect(topology).toContain('sentry');
    expect(topology).toContain('No GPUs');
  });
});

describe('Explanation Generator - Topic Explanations', () => {
  it('should explain GPU topic', () => {
    const clusterState = {
      nodes: [
        { name: 'forge', gpus: { total: 4, used: 2, free: 2 } }
      ]
    };

    const explanation = explainTopic('gpu', clusterState);

    expect(explanation).toBeDefined();
    expect(typeof explanation).toBe('string');
    expect(explanation).toContain('GPU');
    expect(explanation).toContain('Graphics Processing Unit');
  });

  it('should explain leases topic', () => {
    const clusterState = {
      leases: [
        { dseq: '123', owner: 'tenant1', state: 'active' }
      ]
    };

    const explanation = explainTopic('leases', clusterState);

    expect(explanation).toBeDefined();
    expect(explanation).toContain('Lease');
    expect(explanation).toContain('tenant');
  });

  it('should explain provider topic', () => {
    const clusterState = {
      provider: {
        attributes: { 'host': 'akash.network' },
        hostUri: 'https://provider.akash.network'
      }
    };

    const explanation = explainTopic('provider', clusterState);

    expect(explanation).toBeDefined();
    expect(explanation).toContain('Provider');
    expect(explanation).toContain('infrastructure');
  });

  it('should explain blockchain topic', () => {
    const explanation = explainTopic('blockchain', {});

    expect(explanation).toBeDefined();
    expect(explanation).toContain('blockchain');
    expect(explanation).toContain('Akash');
  });

  it('should explain network topic', () => {
    const explanation = explainTopic('network', {});

    expect(explanation).toBeDefined();
    expect(explanation).toContain('network');
    expect(explanation).toContain('communicate');
  });

  it('should return helpful message for unknown topics', () => {
    const explanation = explainTopic('unknown', {});

    expect(explanation).toContain('not available');
    expect(explanation).toContain('gpu');
  });

  it('should include cluster-specific context', () => {
    const clusterState = {
      nodes: [
        { name: 'forge', gpus: { total: 4, used: 2, free: 2 } },
        { name: 'nexus', gpus: { total: 2, used: 0, free: 2 } }
      ]
    };

    const explanation = explainTopic('gpu', clusterState);

    expect(explanation).toContain('forge');
    expect(explanation).toContain('4 GPUs');
    expect(explanation).toContain('2 used');
  });
});

describe('Explanation Generator - Related Topics', () => {
  it('should return related topics for GPU', () => {
    const related = getRelatedTopics('gpu');

    expect(related).toContain('leases');
    expect(related).toContain('provider');
  });

  it('should return related topics for leases', () => {
    const related = getRelatedTopics('leases');

    expect(related).toContain('gpu');
    expect(related).toContain('blockchain');
  });

  it('should return related topics for provider', () => {
    const related = getRelatedTopics('provider');

    expect(related).toContain('gpu');
    expect(related).toContain('network');
  });

  it('should return empty array for unknown topic', () => {
    const related = getRelatedTopics('unknown');

    expect(related).toEqual([]);
  });

  it('should include bidirectional relationships', () => {
    const gpuRelated = getRelatedTopics('gpu');
    const leasesRelated = getRelatedTopics('leases');

    // GPU should reference leases
    expect(gpuRelated).toContain('leases');
    // Leases should reference GPU
    expect(leasesRelated).toContain('gpu');
  });
});
