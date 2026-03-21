/**
 * Knowledge Base and Learning System Tests
 *
 * Test suite for baseline establishment, pattern detection, and documentation retrieval
 */

const {
  establishBaseline,
  getBaseline,
  updateBaseline,
  detectPatterns,
  addToHistory,
  getDocumentation,
  searchDocumentation,
  clearHistory,
  resetBaseline
} = require('../src/knowledge');

describe('Knowledge Base - Baseline System', () => {
  beforeEach(() => {
    resetBaseline();
    clearHistory();
  });

  describe('establishBaseline', () => {
    it('should establish baseline from cluster state', () => {
      const clusterState = {
        nodeCount: 4,
        gpuCount: 7,
        gpuTypes: ['nvidia-rtx3090', 'amd-rx6800'],
        providerVersion: '0.5.0',
        clusterType: 'kubernetes',
        totalCPU: 78,
        totalMemory: 123,
        allocatableGPU: 7,
        namespace: 'akash-services',
        providerStatus: 'active',
        helmRelease: 'akash-provider',
        providerHealthy: true,
        blockchainSynced: true,
        biddingActive: true
      };

      const baseline = establishBaseline(clusterState);

      expect(baseline).toBeDefined();
      expect(baseline.topology.nodeCount).toBe(4);
      expect(baseline.topology.gpuCount).toBe(7);
      expect(baseline.topology.gpuTypes).toEqual(['nvidia-rtx3090', 'amd-rx6800']);
      expect(baseline.topology.providerVersion).toBe('0.5.0');
      expect(baseline.topology.clusterType).toBe('kubernetes');
      expect(baseline.resources.totalCPU).toBe(78);
      expect(baseline.resources.totalMemory).toBe(123);
      expect(baseline.resources.totalGPU).toBe(7);
      expect(baseline.resources.allocatableGPU).toBe(7);
      expect(baseline.provider.namespace).toBe('akash-services');
      expect(baseline.provider.status).toBe('active');
      expect(baseline.provider.helmRelease).toBe('akash-provider');
      expect(baseline.health.providerHealthy).toBe(true);
      expect(baseline.health.blockchainSynced).toBe(true);
      expect(baseline.health.biddingActive).toBe(true);
      expect(baseline.timestamp).toBeDefined();
    });

    it('should handle minimal cluster state with defaults', () => {
      const clusterState = {
        nodeCount: 1,
        gpuCount: 0
      };

      const baseline = establishBaseline(clusterState);

      expect(baseline.topology.nodeCount).toBe(1);
      expect(baseline.topology.gpuCount).toBe(0);
      expect(baseline.topology.providerVersion).toBe('unknown');
      expect(baseline.topology.clusterType).toBe('kubernetes');
      expect(baseline.provider.namespace).toBe('akash-services');
      expect(baseline.health.providerHealthy).toBe(false);
    });

    it('should throw error if cluster state is missing', () => {
      expect(() => {
        establishBaseline(null);
      }).toThrow('Cluster state is required for baseline establishment');
    });

    it('should throw error if cluster state is undefined', () => {
      expect(() => {
        establishBaseline(undefined);
      }).toThrow('Cluster state is required for baseline establishment');
    });
  });

  describe('getBaseline', () => {
    it('should return null when no baseline established', () => {
      const baseline = getBaseline();
      expect(baseline).toBeNull();
    });

    it('should return established baseline', () => {
      const clusterState = {
        nodeCount: 4,
        gpuCount: 7
      };

      establishBaseline(clusterState);
      const baseline = getBaseline();

      expect(baseline).toBeDefined();
      expect(baseline.topology.nodeCount).toBe(4);
      expect(baseline.topology.gpuCount).toBe(7);
    });
  });

  describe('updateBaseline', () => {
    it('should update existing baseline with new values', () => {
      const initialState = {
        nodeCount: 4,
        gpuCount: 7,
        providerVersion: '0.5.0'
      };

      establishBaseline(initialState);

      const updatedState = {
        nodeCount: 5,
        gpuCount: 8,
        providerVersion: '0.6.0'
      };

      const updated = updateBaseline(updatedState);

      expect(updated.topology.nodeCount).toBe(5);
      expect(updated.topology.gpuCount).toBe(8);
      expect(updated.topology.providerVersion).toBe('0.6.0');
      expect(updated.lastUpdated).toBeDefined();
    });

    it('should establish baseline if none exists', () => {
      const clusterState = {
        nodeCount: 3,
        gpuCount: 2
      };

      const baseline = updateBaseline(clusterState);

      expect(baseline).toBeDefined();
      expect(baseline.topology.nodeCount).toBe(3);
      expect(baseline.topology.gpuCount).toBe(2);
    });

    it('should partially update baseline', () => {
      const initialState = {
        nodeCount: 4,
        gpuCount: 7,
        totalCPU: 78,
        totalMemory: 123
      };

      establishBaseline(initialState);

      const partialUpdate = {
        gpuCount: 8
      };

      const updated = updateBaseline(partialUpdate);

      expect(updated.topology.nodeCount).toBe(4); // Unchanged
      expect(updated.topology.gpuCount).toBe(8); // Updated
      expect(updated.resources.totalCPU).toBe(78); // Unchanged
    });

    it('should update health status', () => {
      const initialState = {
        providerHealthy: true,
        blockchainSynced: true,
        biddingActive: true
      };

      establishBaseline(initialState);

      const healthUpdate = {
        providerHealthy: false,
        biddingActive: false
      };

      const updated = updateBaseline(healthUpdate);

      expect(updated.health.providerHealthy).toBe(false);
      expect(updated.health.blockchainSynced).toBe(true); // Unchanged
      expect(updated.health.biddingActive).toBe(false);
    });
  });
});

describe('Knowledge Base - Pattern Detection', () => {
  beforeEach(() => {
    resetBaseline();
    clearHistory();
  });

  describe('detectPatterns', () => {
    it('should detect recurring issues (3+ occurrences)', () => {
      const issue1 = {
        id: 'gpu-not-detected',
        severity: 'high',
        category: 'gpu',
        title: 'GPU Not Detected'
      };

      // Add same issue 3 times to history
      addToHistory(issue1);
      addToHistory(issue1);
      addToHistory(issue1);

      const currentIssues = [];
      const result = detectPatterns(currentIssues);

      expect(result.patterns).toHaveLength(1);
      expect(result.patterns[0].issueId).toBe('gpu-not-detected');
      expect(result.patterns[0].frequency).toBe(3);
      expect(result.patterns[0].isRecurring).toBe(true);
      expect(result.patterns[0].recommendation).toBeDefined();
    });

    it('should not detect pattern for issues appearing less than 3 times', () => {
      const issue1 = {
        id: 'minor-issue',
        severity: 'low',
        category: 'network',
        title: 'Minor Network Issue'
      };

      addToHistory(issue1);
      addToHistory(issue1);

      const result = detectPatterns([]);

      expect(result.patterns).toHaveLength(0);
    });

    it('should count frequency for each issue type', () => {
      const issue1 = {
        id: 'gpu-crash',
        severity: 'high',
        category: 'gpu',
        title: 'GPU Crash'
      };

      const issue2 = {
        id: 'network-timeout',
        severity: 'medium',
        category: 'network',
        title: 'Network Timeout'
      };

      addToHistory(issue1);
      addToHistory(issue1);
      addToHistory(issue1);
      addToHistory(issue2);
      addToHistory(issue2);

      const result = detectPatterns([]);

      expect(result.frequency['gpu-crash'].count).toBe(3);
      expect(result.frequency['network-timeout'].count).toBe(2);
    });

    it('should include current issues in frequency count', () => {
      const issue1 = {
        id: 'provider-down',
        severity: 'critical',
        category: 'provider',
        title: 'Provider Down'
      };

      addToHistory(issue1);
      addToHistory(issue1);

      const currentIssues = [issue1];
      const result = detectPatterns(currentIssues);

      expect(result.frequency['provider-down'].count).toBe(3);
      expect(result.patterns).toHaveLength(1);
    });

    it('should detect severity escalation patterns', () => {
      const issueLow = {
        id: 'memory-pressure',
        severity: 'low',
        category: 'resources',
        title: 'Memory Pressure'
      };

      const issueHigh = {
        id: 'memory-pressure',
        severity: 'high',
        category: 'resources',
        title: 'Memory Pressure'
      };

      addToHistory(issueLow);
      addToHistory(issueHigh);

      const result = detectPatterns([]);

      const escalationPattern = result.patterns.find(p => p.patternType === 'escalation');
      expect(escalationPattern).toBeDefined();
      expect(escalationPattern.issueId).toBe('memory-pressure');
      expect(escalationPattern.severity).toBe('high');
    });

    it('should detect category clustering patterns', () => {
      const gpuIssue1 = {
        id: 'gpu-crash',
        severity: 'high',
        category: 'gpu',
        title: 'GPU Crash'
      };

      const gpuIssue2 = {
        id: 'gpu-memory',
        severity: 'medium',
        category: 'gpu',
        title: 'GPU Memory Error'
      };

      // Add 5 GPU issues
      for (let i = 0; i < 5; i++) {
        addToHistory(gpuIssue1);
      }
      for (let i = 0; i < 5; i++) {
        addToHistory(gpuIssue2);
      }

      const result = detectPatterns([]);

      const categoryPattern = result.patterns.find(p => p.patternType === 'category-cluster');
      expect(categoryPattern).toBeDefined();
      expect(categoryPattern.category).toBe('gpu');
      expect(categoryPattern.frequency).toBeGreaterThanOrEqual(5);
    });

    it('should return total issue count', () => {
      const issue1 = {
        id: 'test-issue',
        severity: 'low',
        category: 'test',
        title: 'Test Issue'
      };

      addToHistory(issue1);
      addToHistory(issue1);
      addToHistory(issue1);

      const currentIssues = [issue1];
      const result = detectPatterns(currentIssues);

      expect(result.totalIssues).toBe(4); // 3 in history + 1 current
    });

    it('should return recurring issue count', () => {
      const issue1 = {
        id: 'recurring-issue',
        severity: 'medium',
        category: 'network',
        title: 'Recurring Issue'
      };

      for (let i = 0; i < 5; i++) {
        addToHistory(issue1);
      }

      const result = detectPatterns([]);

      expect(result.recurringIssueCount).toBeGreaterThan(0);
    });
  });

  describe('addToHistory', () => {
    it('should add issue to history', () => {
      const issue = {
        id: 'test-issue',
        severity: 'high',
        category: 'test',
        title: 'Test Issue'
      };

      const history = addToHistory(issue);

      expect(history).toHaveLength(1);
      expect(history[0].issueId).toBe('test-issue');
      expect(history[0].severity).toBe('high');
      expect(history[0].category).toBe('test');
      expect(history[0].timestamp).toBeDefined();
    });

    it('should not add issue without id', () => {
      const issue = {
        severity: 'high',
        category: 'test',
        title: 'Test Issue'
      };

      const history = addToHistory(issue);

      expect(history).toHaveLength(0);
    });

    it('should not add null issue', () => {
      const history = addToHistory(null);
      expect(history).toHaveLength(0);
    });
  });
});

describe('Knowledge Base - Documentation System', () => {
  describe('getDocumentation', () => {
    it('should retrieve documentation by topic', () => {
      const docs = getDocumentation('provider');

      expect(docs).toBeDefined();
      expect(docs.topic).toBe('provider');
      expect(docs.setup).toBeDefined();
      expect(docs.deployment).toBeDefined();
      expect(docs.attributes).toBeDefined();
    });

    it('should retrieve documentation by subcategory', () => {
      const docs = getDocumentation('setup');

      expect(docs).toBeDefined();
      expect(docs.category).toBeDefined();
      expect(docs.topic).toBe('setup');
      expect(docs.title).toBeDefined();
      expect(docs.content).toBeDefined();
      expect(docs.related).toBeDefined();
    });

    it('should return null for non-existent topic', () => {
      const docs = getDocumentation('non-existent-topic');

      expect(docs).toBeNull();
    });

    it('should retrieve GPU documentation', () => {
      const docs = getDocumentation('gpu');

      expect(docs).toBeDefined();
      expect(docs.topic).toBe('gpu');
      expect(docs.detection).toBeDefined();
      expect(docs['driver-issues']).toBeDefined();
    });

    it('should retrieve troubleshooting documentation', () => {
      const docs = getDocumentation('troubleshooting');

      expect(docs).toBeDefined();
      expect(docs.topic).toBe('troubleshooting');
      expect(docs.logs).toBeDefined();
      expect(docs.events).toBeDefined();
      expect(docs.debug).toBeDefined();
    });
  });

  describe('searchDocumentation', () => {
    it('should search documentation by keyword', () => {
      const results = searchDocumentation('GPU');

      expect(results.length).toBeGreaterThan(0);
      expect(results[0]).toHaveProperty('category');
      expect(results[0]).toHaveProperty('topic');
      expect(results[0]).toHaveProperty('title');
      expect(results[0]).toHaveProperty('content');
      expect(results[0]).toHaveProperty('related');
      expect(results[0]).toHaveProperty('relevance');
    });

    it('should search documentation by phrase', () => {
      const results = searchDocumentation('blockchain sync');

      expect(results.length).toBeGreaterThan(0);
      expect(results[0].content.toLowerCase()).toContain('blockchain');
    });

    it('should return empty array for empty query', () => {
      const results = searchDocumentation('');

      expect(results).toHaveLength(0);
    });

    it('should return empty array for null query', () => {
      const results = searchDocumentation(null);

      expect(results).toHaveLength(0);
    });

    it('should sort results by relevance', () => {
      const results = searchDocumentation('provider');

      expect(results.length).toBeGreaterThan(0);

      // Check that results are sorted by relevance (descending)
      for (let i = 0; i < results.length - 1; i++) {
        expect(results[i].relevance).toBeGreaterThanOrEqual(results[i + 1].relevance);
      }
    });

    it('should find exact title matches with high relevance', () => {
      const results = searchDocumentation('GPU Detection');

      const exactMatch = results.find(r => r.title === 'GPU Detection');
      expect(exactMatch).toBeDefined();
      expect(exactMatch.relevance).toBeGreaterThan(50);
    });

    it('should search in related topics', () => {
      const results = searchDocumentation('leases');

      expect(results.length).toBeGreaterThan(0);
      // Some results should have 'leases' in related topics
      const hasRelated = results.some(r => r.related && r.related.includes('leases'));
      expect(hasRelated).toBe(true);
    });

    it('should truncate long content in results', () => {
      const results = searchDocumentation('provider');

      const longContentResult = results.find(r => r.content.length > 200);
      if (longContentResult) {
        expect(longContentResult.content.endsWith('...')).toBe(true);
      }
    });
  });
});

describe('Knowledge Base - Integration Tests', () => {
  beforeEach(() => {
    resetBaseline();
    clearHistory();
  });

  describe('End-to-end workflow', () => {
    it('should establish baseline and detect patterns over time', () => {
      // 1. Establish baseline
      const clusterState = {
        nodeCount: 4,
        gpuCount: 7,
        providerVersion: '0.5.0',
        providerHealthy: true
      };

      const baseline = establishBaseline(clusterState);
      expect(baseline).toBeDefined();

      // 2. Simulate issues occurring
      const gpuIssue = {
        id: 'gpu-not-detected',
        severity: 'high',
        category: 'gpu',
        title: 'GPU Not Detected'
      };

      for (let i = 0; i < 3; i++) {
        addToHistory(gpuIssue);
      }

      // 3. Detect patterns
      const patterns = detectPatterns([]);
      expect(patterns.patterns).toHaveLength(1);
      expect(patterns.patterns[0].issueId).toBe('gpu-not-detected');

      // 4. Get relevant documentation
      const docs = getDocumentation('gpu');
      expect(docs).toBeDefined();

      // 5. Search for related info
      const searchResults = searchDocumentation('GPU detection');
      expect(searchResults.length).toBeGreaterThan(0);
    });

    it('should track cluster state changes over time', () => {
      // Initial state
      const initialState = {
        nodeCount: 4,
        gpuCount: 7,
        providerHealthy: true,
        blockchainSynced: true
      };

      establishBaseline(initialState);
      expect(getBaseline().topology.gpuCount).toBe(7);

      // GPU added
      updateBaseline({ gpuCount: 8 });
      expect(getBaseline().topology.gpuCount).toBe(8);

      // Provider goes down
      updateBaseline({ providerHealthy: false });
      expect(getBaseline().health.providerHealthy).toBe(false);

      // Verify timestamp updated
      expect(getBaseline().lastUpdated).toBeDefined();
    });

    it('should provide contextual recommendations based on patterns', () => {
      // Add recurring GPU issues
      const gpuIssue = {
        id: 'gpu-crash',
        severity: 'critical',
        category: 'gpu',
        title: 'GPU Crash'
      };

      for (let i = 0; i < 4; i++) {
        addToHistory(gpuIssue);
      }

      const patterns = detectPatterns([]);
      const gpuPattern = patterns.patterns.find(p => p.issueId === 'gpu-crash');

      expect(gpuPattern).toBeDefined();
      expect(gpuPattern.recommendation).toBeDefined();
      expect(gpuPattern.recommendation).toContain('4 times');
    });
  });
});
