---
last-verified: 2026-06-09
verified-by: pipeline-engine
expires: 2026-06-23
---

# Architecture

## Core Tenets
- Nexus (46GB) is default workload node
- Zephyr is source of truth
- All AI traffic goes through AI Gateway on Nexus
- Central SSO via Casdoor + oauth2-proxy + Caddy forward_auth
- All agent orchestration centralized on sentry
- Documentation in docs/LIVE/ is canonical

## Layer Diagram

```
┌──────────────────────────────────────────────────────────┐
│                    EXTERNAL                              │
│  GitHub Issues  GitHub CI  GitHub PR Reviews             │
└─────────────────────┬────────────────────────────────────┘
                      │
┌─────────────────────▼────────────────────────────────────┐
│              SENTRY (orchestrator host)                  │
│                                                          │
│  ┌─────────────────┐    ┌──────────────────────────┐    │
│  │ Reactions Poller│    │ Hermes Gateway             │    │
│  │ (60s, 2 boards) │───▶│ (dispatcher, 60s tick)   │    │
│  └─────────────────┘    └──────────┬───────────────┘    │
│                                    │                    │
│  ┌─────────────────┐    ┌──────────▼───────────────┐    │
│  │ Pipeline Engine │    │ Kanban SQLite Board       │    │
│  │ (on demand)     │───▶│ (tasks,links,runs,events) │    │
│  └─────────────────┘    └──────────────────────────┘    │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │ Agent Profiles                                   │   │
│  │ nixos-eng  maplespike-eng-{1,2,3}  backend-eng  │   │
│  └──────────────────┬───────────────────────────────┘   │
└─────────────────────┼───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│                WORKTREE EXECUTION                       │
│  git worktree add → implement → nix flake check         │
│  → git push origin HEAD → gh pr create --body Closes #N │
└─────────────────────────────────────────────────────────┘
```

## Agent Orchestration

### WORKFLOW.md Contract
Every repo can define a `WORKFLOW.md` with:
- YAML front matter: tracker, polling, workspace, hooks, agent config, proof gates
- Markdown body: prompt template with `{{ issue.number }}` and `{{ attempt }}` variables

The pipeline-engine skill auto-discovers WORKFLOW.md when operating in a repo.

### Pipeline Engine (pipeline-engine skill)
Config-driven pipeline that reads a YAML config and builds kanban task chains:

```
config: pipeline.yaml -> typed PipelineConfig
engine: PipelineEngine.dedup()  -> dedup matches
        PipelineEngine.score()  -> ScoreResult (advance/block)
        PipelineEngine.route()  -> path name (build/fix/shelve)
        PipelineEngine.research_specs()  -> parallel task specs
        PipelineEngine.prep_specs()      -> chained prep specs
        PipelineEngine.fulfillment_specs() -> chained fulfillment specs
```

### Reactions Poller
Two systemd services on sentry polling GitHub every 60s:
- CI failure -> creates fix(ci): kanban task
- Review changes_requested -> creates rework: kanban task
- PR merged -> closes related kanban tasks

### Boards
- nixos-config (reverb256/nixos-config) - infrastructure tasks
- maplespike (reverb256/maplespike) - data module development

### Profiles
All profiles have 3-tier fallback: opencode-go -> nvidia -> zai
- nixos-eng: nixos-cluster-conventions, nixos-eval-debug, colmena-cluster-deploy
- maplespike-eng-{1,2,3}: maplespike skills
- backend-eng, frontend-eng, analyst, researcher, writer
