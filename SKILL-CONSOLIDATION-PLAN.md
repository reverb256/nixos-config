# Skill Consolidation Plan

**Date**: 2026-03-07
**Status**: Planning Phase
**Current Skill Count**: ~90
**Target Count**: ~40
**Projected Reduction**: -50 skills (~55%)

---

## Executive Summary

This document details the consolidation of redundant skills in the agent skill system. Skills are grouped by functional area, with specific merge specifications, safety assessments, and migration paths.

---

## Phase 1: Assessment Update

### 1.1 Finding: No Exact Duplicates Exist

After investigation, the suspected duplicates were false positives:

| Suspected Duplicate | Actual Status | Reason |
|---------------------|---------------|--------|
| `vercel:deploy` | Not duplicate | Single skill at `~/.claude/plugins/cache/claude-plugins-official/vercel/1.0.0/skills/deploy/` |
| `vercel:setup` | Not duplicate | Single skill at `~/.claude/plugins/cache/claude-plugins-official/vercel/1.0.0/skills/setup/` |
| `vercel:logs` | Not duplicate | Single skill at `~/.claude/plugins/cache/claude-plugins-official/vercel/1.0.0/skills/logs/` |
| `glm-plan-usage:usage-query` | Not duplicate | Agent and skill serve different purposes |
| `glm-plan-bug:case-feedback` | Not duplicate | Agent and skill serve different purposes |

**The apparent duplicates in the system reminder were caused by:**
- Same skills being scanned from both `commands/` and `skills/` directories
- Agent-skill pairs that complement each other (agent = user interaction, skill = script execution)

**Action**: Skip to Phase 2 (Functional Consolidation)

---

## Phase 2: High-Confidence Merges (Low Risk)

### 2.1 Documentation Skills → `documentation:complete`

**Current Skills**:
- `technical-writing`
- `documentation-writer` (Diátaxis framework)
- `writing-clearly-and-concisely`

**Consolidated Into**: `documentation:complete`

**Merge Specification**:
```yaml
name: documentation:complete
description: Complete technical writing and documentation expertise

components:
  - framework: Diátaxis (tutorials, how-to guides, reference, explanation)
  - clarity: Writing clearly and concisely principles
  - technical: API docs, READMEs, inline comments

from_skills:
  - documentation-writer (core - keep Diátaxis framework)
  - technical-writing (merge as additional patterns)
  - writing-clearly-and-concisely (merge as style guide)
```

**Safe to Remove**: `technical-writing`, `writing-clearly-and-concisely`
**Keep**: `documentation-writer` → rename to `documentation:complete`

**Migration Path**:
1. Read all three skill files
2. Extract unique content from `technical-writing` and `writing-clearly-and-concisely`
3. Merge into `documentation-writer`
4. Rename to `documentation:complete`
5. Delete old files

---

### 2.2 NixOS Skills → `nixos:complete`

**Current Skills**:
- `nixos-best-practices`
- `nix-ecosystem`

**Consolidated Into**: `nixos:complete`

**Merge Specification**:
```yaml
name: nixos:complete
description: Complete NixOS and Nix ecosystem expertise

components:
  - best_practices: Flake patterns, module structure, testing
  - ecosystem: Nixpkgs, NixOS, Nix wrappers, community tools
  - workflows: Building, testing, rollback, debugging

from_skills:
  - nixos-best-practices (base)
  - nix-ecosystem (merge ecosystem overview)
```

**Safe to Remove**: `nix-ecosystem`
**Keep**: `nixos-best-practices` → rename to `nixos:complete`

---

### 2.3 Docker Skills → `docker:complete`

**Current Skills**:
- `docker-best-practices`
- `docker-patterns`
- `docker-compose-orchestration`

**Consolidated Into**: `docker:complete`

**Merge Specification**:
```yaml
name: docker:complete
description: Complete Docker and Docker Compose expertise

components:
  - best_practices: Security, performance, image optimization
  - patterns: Multi-stage builds, compose patterns, volumes
  - orchestration: Docker Compose for local development

from_skills:
  - docker-best-practices (merge into patterns)
  - docker-patterns (base)
  - docker-compose-orchestration (merge as compose section)
```

**Safe to Remove**: `docker-best-practices`
**Keep**: `docker-patterns` → rename to `docker:complete`, absorb compose content

---

### 2.4 Kubernetes Skills → `kubernetes:core`

**Current Skills**:
- `kubernetes-architect`
- `k8s-manifest-generator`
- `k8s-security-policies`
- `k8s-helm`

**Consolidated Into**: `kubernetes:core`

**Merge Specification**:
```yaml
name: kubernetes:core
description: Complete Kubernetes expertise including Helm

components:
  - architecture: Cluster design, patterns, best practices
  - manifests: Generate production-ready K8s manifests
  - security: Policies, RBAC, network policies
  - helm: Charts and templating

from_skills:
  - kubernetes-architect (base architecture)
  - k8s-manifest-generator (merge manifest patterns)
  - k8s-security-policies (merge security section)
  - k8s-helm (keep as submodule or merge)
```

**Safe to Remove**: `k8s-manifest-generator`, `k8s-security-policies`
**Keep**: `kubernetes-architect` → rename to `kubernetes:core`
**Decision Point**: `k8s-helm` - could be separate `kubernetes:helm` or merged

---

## Phase 3: Marketing/SEO Skills (Major Consolidation)

### 3.1 Marketing Skills Overview

**Current Count**: 30+ skills across SEO, CRO, content, growth, outbound

**Proposed Structure**:
```
marketing:/
  ├── seo (ai-seo, programmatic-seo, schema-markup, site-architecture)
  ├── cro (page-cro, signup-flow-cro, popup-cro, onboarding-cro, paywall-upgrade-cro, form-cro)
  ├── content (copywriting, copy-editing, content-strategy, social-content, ux-writing)
  ├── growth (launch-strategy, referral-program, pricing-strategy, viral-loops)
  ├── outbound (cold-email, email-sequence, sales-enablement, paid-ads, ad-creative)
  ├── analytics (churn-prevention, revops, analytics-tracking, business-intelligence)
  ├── product (ai-product-strategy, product-marketing-context, competitor-alternatives)
  └── psychology (marketing-psychology, fogg-behavior-model, free-tool-strategy)
```

**Detailed Merge Specifications**:

#### `marketing:seo`
```yaml
from_skills:
  - ai-seo (base)
  - programmatic-seo (merge)
  - schema-markup (merge)
  - site-architecture (merge)

remove:
  - programmatic-seo
  - schema-markup
  - site-architecture
```

#### `marketing:cro`
```yaml
from_skills:
  - page-cro (base)
  - signup-flow-cro (merge)
  - popup-cro (merge)
  - onboarding-cro (merge)
  - paywall-upgrade-cro (merge)
  - form-cro (merge)

remove:
  - signup-flow-cro
  - popup-cro
  - onboarding-cro
  - paywall-upgrade-cro
  - form-cro
```

#### `marketing:content`
```yaml
from_skills:
  - copywriting (base)
  - copy-editing (merge)
  - content-strategy (merge)
  - social-content (merge)
  - ux-writing (merge)

remove:
  - copy-editing
  - content-strategy
  - social-content
  - ux-writing
```

#### `marketing:growth`
```yaml
from_skills:
  - launch-strategy (base)
  - referral-program (merge)
  - pricing-strategy (merge)

remove:
  - referral-program
  - pricing-strategy
```

#### `marketing:outbound`
```yaml
from_skills:
  - cold-email (base)
  - email-sequence (merge)
  - sales-enablement (merge)
  - paid-ads (merge)
  - ad-creative (merge)

remove:
  - email-sequence
  - sales-enablement
  - paid-ads
  - ad-creative
```

#### `marketing:analytics`
```yaml
from_skills:
  - analytics-tracking (base)
  - churn-prevention (merge)
  - revops (merge)
  - business-intelligence (merge)

remove:
  - churn-prevention
  - revops
  - business-intelligence
```

#### `marketing:product`
```yaml
from_skills:
  - ai-product-strategy (base)
  - product-marketing-context (merge)
  - competitor-alternatives (merge)
  - ab-test-setup (merge)

remove:
  - product-marketing-context
  - competitor-alternatives
  - ab-test-setup
```

#### `marketing:psychology`
```yaml
from_skills:
  - marketing-psychology (base)
  - fogg-behavior-model (merge)
  - free-tool-strategy (merge)

remove:
  - fogg-behavior-model
  - free-tool-strategy
```

---

## Phase 4: ComfyUI Consolidation

### 4.1 ComfyUI Skills → 4 Core Skills

**Current Skills** (12):
- comfyui-api
- comfyui-character-gen
- comfyui-inventory
- comfyui-lora-training
- comfyui-prompt-engineer
- comfyui-prompt-interview
- comfyui-research
- comfyui-troubleshooter
- comfyui-video-pipeline
- comfyui-voice-pipeline
- comfyui-workflow-builder
- comfyui-nodes-dev

**Proposed Structure**:
```
comfyui:/
  ├── core (api, inventory, research, troubleshooter)
  ├── workflow (workflow-builder, prompt-engineer, prompt-interview, character-gen)
  ├── pipelines (video-pipeline, voice-pipeline, lora-training)
  └── dev (nodes-dev)
```

#### `comfyui:core`
```yaml
from_skills:
  - comfyui-api (base)
  - comfyui-inventory (merge)
  - comfyui-research (merge)
  - comfyui-troubleshooter (merge)

remove:
  - comfyui-inventory
  - comfyui-research
  - comfyui-troubleshooter
```

#### `comfyui:workflow`
```yaml
from_skills:
  - comfyui-workflow-builder (base)
  - comfyui-prompt-engineer (merge)
  - comfyui-prompt-interview (merge)
  - comfyui-character-gen (merge)

remove:
  - comfyui-prompt-engineer
  - comfyui-prompt-interview
  - comfyui-character-gen
```

#### `comfyui:pipelines`
```yaml
from_skills:
  - comfyui-video-pipeline (base)
  - comfyui-voice-pipeline (merge)
  - comfyui-lora-training (merge)

remove:
  - comfyui-voice-pipeline
  - comfyui-lora-training
```

#### `comfyui:dev`
```yaml
from_skills:
  - comfyui-nodes-dev (keep as-is)

remove: none
```

---

## Phase 5: Pinecone Consolidation

### 5.1 Pinecone Skills → 3 Core Skills

**Current Skills** (7):
- pinecone:assistant
- pinecone:cli
- pinecone:query
- pinecone:help
- pinecone:docs
- pinecone:mcp
- pinecone:quickstart
- pinecone:join-discord

**Proposed Structure**:
```
pinecone:/
  ├── guide (help, docs, quickstart, join-discord)
  ├── usage (assistant, cli, query)
  └── mcp (mcp)
```

#### `pinecone:guide`
```yaml
from_skills:
  - pinecone:help (base)
  - pinecone:docs (merge)
  - pinecone:quickstart (merge)
  - pinecone:join-discord (merge as link)

remove:
  - pinecone:docs
  - pinecone:quickstart
  - pinecone:join-discord
```

#### `pinecone:usage`
```yaml
from_skills:
  - pinecone:assistant (base)
  - pinecone:cli (merge)
  - pinecone:query (merge)

remove:
  - pinecone:cli
  - pinecone:query
```

#### `pinecone:mcp`
```yaml
from_skills:
  - pinecone:mcp (keep as-is)

remove: none
```

---

## Phase 6: HuggingFace Skills

### 6.1 HuggingFace Cleanup

**Current Skills** (10):
- hugging-face-cli
- hugging-face-dataset-viewer
- hugging-face-datasets
- hugging-face-evaluation
- hugging-face-tool-builder
- hugging-face-paper-publisher
- hugging-face-trackio
- hugging-face-jobs
- hugging-face-model-trainer
- hugging-face-gradio

**Potential Merge**:
```yaml
huggingface:datasets (merge viewer + datasets)
  from:
    - hugging-face-datasets (base)
    - hugging-face-dataset-viewer (merge)

remove:
  - hugging-face-dataset-viewer
```

**Keep Separate** (distinct functionality):
- hugging-face-cli (tool operations)
- hugging-face-evaluation (metrics)
- hugging-face-tool-builder (MCP tools)
- hugging-face-paper-publisher (publishing)
- hugging-face-trackio (experiment tracking)
- hugging-face-jobs (training jobs)
- hugging-face-model-trainer (training)
- hugging-face-gradio (UI building)

---

## Phase 7: Game Design Skills

### 7.1 Game Skills → 2 Core Skills

**Current Skills** (5):
- game-ui-design
- game-designer
- dramatic-2000ms-plus
- micro-interactions
- emotional-narrative

**Proposed Structure**:
```
game:/
  ├── design (game-ui-design, game-designer)
  └── animation (dramatic-2000ms-plus, micro-interactions, emotional-narrative)
```

#### `game:design`
```yaml
from_skills:
  - game-ui-design (base)
  - game-designer (merge)

remove:
  - game-designer
```

#### `game:animation`
```yaml
from_skills:
  - dramatic-2000ms-plus (base)
  - micro-interactions (merge)
  - emotional-narrative (merge)

remove:
  - micro-interactions
  - emotional-narrative
```

---

## Phase 8: Notion Skills

### 8.1 Notion Cleanup

**Current Skills** (10):
- Notion:create-database-row
- Notion:create-page
- Notion:create-task
- Notion:database-query
- Notion:find
- Notion:search
- Notion:tasks:build
- Notion:tasks:explain-diff
- Notion:tasks:plan
- Notion:tasks:setup

**Potential Merge**:
```yaml
Notion:find (merge find + search)
  from:
    - Notion:find (base)
    - Notion:search (merge)

remove:
  - Notion:search
```

**Keep Separate**: All others have distinct purposes

---

## Phase 9: Frontend/Web Skills

### 9.1 Web Skills Review

**Current Skills**:
- astro (framework-specific)
- web-design-guidelines (review patterns)
- generative-ui (AI generation)
- frontend-design (design-focused)
- accessibility (audit)
- web-perf (performance)
- top-design (award-winning)
- animate (animation)

**Recommendation**: Keep most separate as they serve distinct purposes:
- Framework-specific (astro) - keep
- Review/audit (accessibility, web-perf, web-design-guidelines) - keep
- Design (frontend-design, generative-ui, top-design) - could consolidate
- Animation (animate) - keep separate

**Optional Merge**: `frontend:design` (frontend-design + generative-ui + top-design)

---

## Safe Removal List (No Migration Needed)

**Update**: No exact duplicates found. All skills serve unique purposes or are agent-skill pairs with distinct functions.

| Suspected Duplicate | Actual Status | Reason |
|---------------------|---------------|--------|
| `vercel:deploy` | Not duplicate | Single skill, listed twice due to directory scanning |
| `vercel:setup` | Not duplicate | Single skill, listed twice due to directory scanning |
| `vercel:logs` | Not duplicate | Single skill, listed twice due to directory scanning |
| `glm-plan-usage:usage-query` | Not duplicate | Agent and skill serve different purposes |
| `glm-plan-bug:case-feedback` | Not duplicate | Agent and skill serve different purposes |

**Note**: All consolidations require merging content, not simple deletion.

---

## Execution Order

### ~~Priority 1~~: ~~Quick Wins (Exact Duplicates)~~ ✗ No exact duplicates found

**Finding**: The suspected duplicates were false positives:
- Vercel skills: Single instances, listed twice due to commands/ + skills/ directory scanning
- GLM-plan skills: Agent-skill pairs serve different purposes (interaction vs execution)

---

### Priority 1: Low-Risk Functional Merges (3-5 skills each)

**Why start here**: These skills have significant overlap in content and purpose.

1. **Documentation** → `documentation:complete` (3→1)
   - `technical-writing` + `documentation-writer` (Diátaxis) + `writing-clearly-and-concisely`

2. **NixOS** → `nixos:complete` (2→1)
   - `nixos-best-practices` + `nix-ecosystem`

3. **Docker** → `docker:complete` (3→1)
   - `docker-best-practices` + `docker-patterns` + `docker-compose-orchestration`

4. **Kubernetes** → `kubernetes:core` (4→1)
   - `kubernetes-architect` + `k8s-manifest-generator` + `k8s-security-policies` + `k8s-helm`

---

### Priority 2: Medium-Risk Domain Consolidations (5-10 skills each)

1. **Marketing** → `marketing:*` (30+→8 skills)
   - seo, cro, content, growth, outbound, analytics, product, psychology

2. **ComfyUI** → `comfyui:*` (12→4 skills)
   - core, workflow, pipelines, dev

3. **Pinecone** → `pinecone:*` (7→3 skills)
   - guide, usage, mcp

---

### Priority 3: Minor Consolidations

1. **HuggingFace** (10→9)
   - Merge `hugging-face-datasets` + `hugging-face-dataset-viewer`

2. **Game Design** (5→2)
   - `game:design` (game-ui-design + game-designer)
   - `game:animation` (dramatic-2000ms-plus + micro-interactions + emotional-narrative)

3. **Notion** (10→9)
   - Merge `Notion:find` + `Notion:search`

---

## Migration Template

When merging skills, use this template:

```markdown
# Merging [Source Skills] → [Target Skill]

## Step 1: Backup
```bash
cp -r skills/source skills/source.backup
```

## Step 2: Read Source Skills
```bash
# List all source skill files
ls skills/source-*
cat skills/source-1.md
cat skills/source-2.md
```

## Step 3: Create Consolidated Skill
```markdown
# [Target Skill Name]

## Description
[Combined description]

## Components
- [Component 1 from source-1]
- [Component 2 from source-2]

## Triggers
[Combined trigger conditions]

## Checklist
[Merged checklists]
```

## Step 4: Test
[Verify skill works as expected]

## Step 5: Remove Old Skills
```bash
rm skills/source-1.md skills/source-2.md
```
```

---

## Risk Assessment Matrix

| Merge | Risk Level | Rollback Complexity | Notes |
|-------|------------|---------------------|-------|
| Exact duplicates | 🟢 Low | Trivial | Just delete extras |
| Documentation | 🟢 Low | Low | Similar content |
| NixOS | 🟢 Low | Low | Complementary content |
| Docker | 🟢 Low | Low | Overlapping patterns |
| Kubernetes | 🟡 Medium | Medium | More complex domain |
| Marketing | 🟡 Medium | High | Many small skills |
| ComfyUI | 🟡 Medium | Medium | Domain-specific |
| Pinecone | 🟢 Low | Low | Well-organized |
| HuggingFace | 🟢 Low | Low | One merge |
| Game | 🟢 Low | Low | Clear separation |
| Notion | 🟢 Low | Low | One merge |

---

## Success Metrics

- [ ] Total skill count reduced from ~90 to ~40
- [ ] No functionality lost (all original use cases covered)
- [ ] Skill names follow consistent naming convention (category:feature)
- [ ] Each skill has clear, non-overlapping trigger conditions
- [ ] Documentation updated for all merged skills

---

## Next Steps

1. ✅ Create this consolidation plan
2. ⏳ Get approval for Priority 1 and 2 changes
3. ⏳ Execute Priority 1 (exact duplicates)
4. ⏳ Execute Priority 2 (low-risk merges)
5. ⏳ Test consolidated skills
6. ⏳ Proceed to Priority 3 and 4
7. ⏳ Final review and documentation update
