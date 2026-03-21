# Akash Assistant Skill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an intelligent Akash Network provider assistant skill for AI agents that diagnoses issues, explains cluster state in plain language with visuals, and automatically fixes common problems.

**Architecture:** Unified skill entry point (`/akash`) with 5 core components: Diagnostics Engine, Prioritization System, Explanation Generator, Auto-Fix Module, and Knowledge Base. Dual output format (JSON for agents, Markdown for humans).

**Tech Stack:** Node.js/JavaScript, Kubernetes API (kubectl), Claude Code skill system, Serena tools integration

---

## Task 1: Create Skill Structure

**Files:**
- Create: `.claude/skills/akash/SKILL.md`
- Create: `.claude/skills/akash/package.json`
- Create: `.claude/skills/akash/src/index.js`
- Create: `.claude/skills/akash/src/diagnostics.js`
- Create: `.claude/skills/akash/src/prioritizer.js`
- Create: `.claude/skills/akash/src/explainer.js`
- Create: `.claude/skills/akash/src/auto-fix.js`
- Create: `.claude/skills/akash/src/knowledge.js`
- Create: `.claude/skills/akash/tests/diagnostics.test.js`
- Create: `.claude/skills/akash/.gitignore`

**Step 1: Create SKILL.md metadata file**

Create `.claude/skills/akash/SKILL.md` with skill metadata including overview, commands, and examples.

**Step 2: Create package.json**

Create `.claude/skills/akash/package.json` with dependencies and scripts.

**Step 3: Create main entry point**

Create `.claude/skills/akash/src/index.js` with command routing and handlers.

**Step 4: Create .gitignore**

Create `.claude/skills/akash/.gitignore` with node_modules and build artifacts.

**Step 5: Commit skill structure**

Run: `git add .claude/skills/akash/`
Run: `git commit -m "feat(akash): create skill structure and entry point"`

---

## Task 2: Implement Diagnostics Engine

**Files:**
- Create: `.claude/skills/akash/src/diagnostics.js`
- Create: `.claude/skills/akash/src/utils/kubectl.js`
- Test: `.claude/skills/akash/tests/diagnostics.test.js`

**Step 1: Write failing test for provider health check**

Create test file with tests for provider health detection.

**Step 2: Run test to verify it fails**

Run: `cd .claude/skills/akash && npm test`
Expected: FAIL

**Step 3: Implement kubectl utility**

Create kubectl wrapper for Kubernetes API interactions.

**Step 4: Implement provider health check**

Implement checkProviderHealth function with status detection.

**Step 5: Run test to verify it passes**

Run tests and verify all pass.

**Step 6: Commit diagnostics engine**

Run: `git add .claude/skills/akash/src/diagnostics.js .claude/skills/akash/src/utils/kubectl.js`
Run: `git commit -m "feat(akash): implement provider health diagnostics"`

---

## Task 3: Implement Prioritization System

**Files:**
- Create: `.claude/skills/akash/src/prioritizer.js`
- Test: `.claude/skills/akash/tests/prioritizer.test.js`

**Step 1: Write failing test for issue prioritization**

Create tests for issue scoring and sorting.

**Step 2: Run test to verify it fails**

Expected: FAIL

**Step 3: Implement prioritization system**

Create prioritizeIssues function with scoring algorithm.

**Step 4: Run test to verify it passes**

Verify all tests pass.

**Step 5: Commit prioritization system**

Run: `git commit -m "feat(akash): implement issue prioritization system"`

---

## Task 4: Implement Explanation Generator

**Files:**
- Create: `.claude/skills/akash/src/explainer.js`
- Test: `.claude/skills/akash/tests/explainer.test.js`

**Step 1: Write failing test for report generation**

Create tests for markdown report and ASCII topology generation.

**Step 2: Run test to verify it fails**

Expected: FAIL

**Step 3: Implement explanation generator**

Create generateReport and generateTopology functions.

**Step 4: Run test to verify it passes**

Verify tests pass.

**Step 5: Commit explanation generator**

Run: `git commit -m "feat(akash): implement explanation generator with ASCII topology"`

---

## Task 5: Implement Auto-Fix Module

**Files:**
- Create: `.claude/skills/akash/src/auto-fix.js`
- Create: `.claude/skills/akash/src/utils/fixes.js`
- Test: `.claude/skills/akash/tests/auto-fix.test.js`

**Step 1: Write failing test for auto-fix**

Create tests for automatic and permission-required fixes.

**Step 2: Run test to verify it fails**

Expected: FAIL

**Step 3: Implement fix utilities**

Create kubectl-based fix functions (deletePod, restartDeployment, etc.).

**Step 4: Implement auto-fix module**

Create attemptAutoFix with permission handling.

**Step 5: Run test to verify it passes**

Verify tests pass.

**Step 6: Commit auto-fix module**

Run: `git commit -m "feat(akash): implement auto-fix module with permission system"`

---

## Task 6: Implement Knowledge Base

**Files:**
- Create: `.claude/skills/akash/src/knowledge.js`
- Create: `.claude/skills/akash/data/akash-docs.json`
- Test: `.claude/skills/akash/tests/knowledge.test.js`

**Step 1: Write failing test for knowledge base**

Create tests for baseline establishment and pattern detection.

**Step 2: Run test to verify it fails**

Expected: FAIL

**Step 3: Implement knowledge base**

Create learning system with audit history and pattern detection.

**Step 4: Create Akash documentation**

Create built-in Akash Network reference documentation.

**Step 5: Run test to verify it passes**

Verify tests pass.

**Step 6: Commit knowledge base**

Run: `git commit -m "feat(akash): implement knowledge base with learning system"`

---

## Task 7: Complete Diagnostics Integration

**Files:**
- Modify: `.claude/skills/akash/src/diagnostics.js`
- Test: `.claude/skills/akash/tests/integration.test.js`

**Step 1: Write integration test for full diagnostics**

Create test for complete diagnostic workflow.

**Step 2: Complete diagnostics implementation**

Add remaining check functions (hardware discovery, GPU inventory, etc.).

**Step 3: Run integration tests**

Verify all integration tests pass.

**Step 4: Commit complete diagnostics**

Run: `git commit -m "feat(akash): complete diagnostics integration with all checks"`

---

## Task 8: Add Skill Documentation

**Files:**
- Create: `.claude/skills/akash/README.md`
- Create: `.claude/skills/akash/CHANGELOG.md`

**Step 1: Create comprehensive README**

Create user-facing documentation with examples.

**Step 2: Commit documentation**

Run: `git commit -m "docs(akash): add comprehensive README and changelog"`

---

## Task 9: Integration Testing with Real Cluster

**Files:**
- Create: `.claude/skills/akash/tests/cluster-test.sh`

**Step 1: Create cluster integration test script**

Create bash script for real cluster testing.

**Step 2: Make script executable and run**

Verify all cluster tests pass.

**Step 3: Commit integration test**

Run: `git commit -m "test(akash): add cluster integration test script"`

---

## Task 10: Final Polish and Documentation

**Files:**
- Create: `.claude/skills/akash/docs/training-guide.md`
- Update: `.claude/skills/akash/package.json`

**Step 1: Create training guide for agents**

Create documentation for AI agent integration.

**Step 2: Update package.json with additional scripts**

Add demo and integration test scripts.

**Step 3: Create final documentation**

Create implementation completion summary.

**Step 4: Final commit**

Run: `git commit -m "feat(akash): complete implementation - all features working"`

---

**Total Tasks: 10**
**Estimated Time: 4-6 hours**
**Dependencies: Each task builds on previous ones, execute sequentially**
