/**
 * Prioritization System Tests
 *
 * Test suite for issue scoring, ranking, and categorization
 */

const {
  calculateScore,
  prioritizeIssues,
  categorizeIssues
} = require('../src/prioritizer');

describe('Prioritization System - Score Calculation', () => {
  describe('calculateScore', () => {
    const baseScores = {
      critical: 100,
      high: 50,
      medium: 20,
      low: 5
    };

    it('should calculate base score for critical severity', () => {
      const issue = {
        severity: 'critical',
        impact: [],
        urgency: []
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.critical);
    });

    it('should calculate base score for high severity', () => {
      const issue = {
        severity: 'high',
        impact: [],
        urgency: []
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.high);
    });

    it('should calculate base score for medium severity', () => {
      const issue = {
        severity: 'medium',
        impact: [],
        urgency: []
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.medium);
    });

    it('should calculate base score for low severity', () => {
      const issue = {
        severity: 'low',
        impact: [],
        urgency: []
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.low);
    });

    it('should add revenue impact modifier (+20)', () => {
      const issue = {
        severity: 'high',
        impact: ['revenue'],
        urgency: []
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.high + 20); // 50 + 20 = 70
    });

    it('should add multiple nodes impact modifier (+15)', () => {
      const issue = {
        severity: 'high',
        impact: ['multiple-nodes'],
        urgency: []
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.high + 15); // 50 + 15 = 65
    });

    it('should add blocks leases impact modifier (+25)', () => {
      const issue = {
        severity: 'critical',
        impact: ['blocks-leases'],
        urgency: []
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.critical + 25); // 100 + 25 = 125
    });

    it('should add degrading urgency modifier (+10)', () => {
      const issue = {
        severity: 'medium',
        impact: [],
        urgency: ['degrading']
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.medium + 10); // 20 + 10 = 30
    });

    it('should add user complaints urgency modifier (+15)', () => {
      const issue = {
        severity: 'medium',
        impact: [],
        urgency: ['user-complaints']
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.medium + 15); // 20 + 15 = 35
    });

    it('should combine multiple impact modifiers', () => {
      const issue = {
        severity: 'high',
        impact: ['revenue', 'multiple-nodes'],
        urgency: []
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.high + 20 + 15); // 50 + 20 + 15 = 85
    });

    it('should combine multiple urgency modifiers', () => {
      const issue = {
        severity: 'medium',
        impact: [],
        urgency: ['degrading', 'user-complaints']
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.medium + 10 + 15); // 20 + 10 + 15 = 45
    });

    it('should combine all modifiers (maximum score)', () => {
      const issue = {
        severity: 'critical',
        impact: ['revenue', 'multiple-nodes', 'blocks-leases'],
        urgency: ['degrading', 'user-complaints']
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.critical + 20 + 15 + 25 + 10 + 15); // 100 + 85 = 185
    });

    it('should handle low severity with no modifiers', () => {
      const issue = {
        severity: 'low',
        impact: [],
        urgency: []
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.low); // 5
    });

    it('should be case-insensitive for severity', () => {
      const issue = {
        severity: 'CRITICAL',
        impact: [],
        urgency: []
      };

      const score = calculateScore(issue);
      expect(score).toBe(baseScores.critical);
    });
  });
});

describe('Prioritization System - Issue Ranking', () => {
  describe('prioritizeIssues', () => {
    it('should sort issues by score descending', () => {
      const issues = [
        {
          id: 'issue-1',
          severity: 'low',
          impact: [],
          urgency: []
        },
        {
          id: 'issue-2',
          severity: 'critical',
          impact: [],
          urgency: []
        },
        {
          id: 'issue-3',
          severity: 'medium',
          impact: [],
          urgency: []
        }
      ];

      const prioritized = prioritizeIssues(issues);

      expect(prioritized[0].id).toBe('issue-2');
      expect(prioritized[0].priority).toBe(1);
      expect(prioritized[0].score).toBe(100);

      expect(prioritized[1].id).toBe('issue-3');
      expect(prioritized[1].priority).toBe(2);
      expect(prioritized[1].score).toBe(20);

      expect(prioritized[2].id).toBe('issue-1');
      expect(prioritized[2].priority).toBe(3);
      expect(prioritized[2].score).toBe(5);
    });

    it('should assign sequential priority numbers starting at 1', () => {
      const issues = [
        { id: 'a', severity: 'medium', impact: [], urgency: [] },
        { id: 'b', severity: 'high', impact: [], urgency: [] },
        { id: 'c', severity: 'low', impact: [], urgency: [] }
      ];

      const prioritized = prioritizeIssues(issues);

      expect(prioritized[0].priority).toBe(1);
      expect(prioritized[1].priority).toBe(2);
      expect(prioritized[2].priority).toBe(3);
    });

    it('should handle empty array', () => {
      const prioritized = prioritizeIssues([]);
      expect(prioritized).toEqual([]);
    });

    it('should handle single issue', () => {
      const issues = [
        { id: 'only', severity: 'high', impact: [], urgency: [] }
      ];

      const prioritized = prioritizeIssues(issues);

      expect(prioritized).toHaveLength(1);
      expect(prioritized[0].priority).toBe(1);
      expect(prioritized[0].score).toBe(50);
    });

    it('should sort by score when severities are equal', () => {
      const issues = [
        {
          id: 'issue-1',
          severity: 'high',
          impact: [],
          urgency: ['degrading'] // +10 = 60
        },
        {
          id: 'issue-2',
          severity: 'high',
          impact: ['revenue'], // +20 = 70
          urgency: []
        },
        {
          id: 'issue-3',
          severity: 'high',
          impact: [],
          urgency: [] // 50
        }
      ];

      const prioritized = prioritizeIssues(issues);

      expect(prioritized[0].id).toBe('issue-2');
      expect(prioritized[0].score).toBe(70);

      expect(prioritized[1].id).toBe('issue-1');
      expect(prioritized[1].score).toBe(60);

      expect(prioritized[2].id).toBe('issue-3');
      expect(prioritized[2].score).toBe(50);
    });

    it('should preserve all original issue properties', () => {
      const issues = [
        {
          id: 'test-1',
          severity: 'critical',
          impact: ['revenue'],
          urgency: ['degrading'],
          description: 'Test issue',
          component: 'provider'
        }
      ];

      const prioritized = prioritizeIssues(issues);

      expect(prioritized[0].id).toBe('test-1');
      expect(prioritized[0].description).toBe('Test issue');
      expect(prioritized[0].component).toBe('provider');
      expect(prioritized[0].priority).toBeDefined();
      expect(prioritized[0].score).toBeDefined();
    });
  });
});

describe('Prioritization System - Issue Categorization', () => {
  describe('categorizeIssues', () => {
    it('should group issues by severity', () => {
      const issues = [
        { id: 'c1', severity: 'critical', impact: [], urgency: [] },
        { id: 'h1', severity: 'high', impact: [], urgency: [] },
        { id: 'm1', severity: 'medium', impact: [], urgency: [] },
        { id: 'l1', severity: 'low', impact: [], urgency: [] },
        { id: 'c2', severity: 'critical', impact: [], urgency: [] }
      ];

      const categorized = categorizeIssues(issues);

      expect(categorized.critical).toHaveLength(2);
      expect(categorized.high).toHaveLength(1);
      expect(categorized.medium).toHaveLength(1);
      expect(categorized.low).toHaveLength(1);

      expect(categorized.critical.map(i => i.id)).toEqual(['c1', 'c2']);
      expect(categorized.high.map(i => i.id)).toEqual(['h1']);
      expect(categorized.medium.map(i => i.id)).toEqual(['m1']);
      expect(categorized.low.map(i => i.id)).toEqual(['l1']);
    });

    it('should return empty arrays for missing severities', () => {
      const issues = [
        { id: 'h1', severity: 'high', impact: [], urgency: [] }
      ];

      const categorized = categorizeIssues(issues);

      expect(categorized.critical).toEqual([]);
      expect(categorized.high).toHaveLength(1);
      expect(categorized.medium).toEqual([]);
      expect(categorized.low).toEqual([]);
    });

    it('should handle empty array', () => {
      const categorized = categorizeIssues([]);

      expect(categorized.critical).toEqual([]);
      expect(categorized.high).toEqual([]);
      expect(categorized.medium).toEqual([]);
      expect(categorized.low).toEqual([]);
    });

    it('should be case-insensitive for severity', () => {
      const issues = [
        { id: 'c1', severity: 'CRITICAL', impact: [], urgency: [] },
        { id: 'c2', severity: 'Critical', impact: [], urgency: [] }
      ];

      const categorized = categorizeIssues(issues);

      expect(categorized.critical).toHaveLength(2);
    });
  });
});
