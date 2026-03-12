# j-kro's Agent Federation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy a 6-agent Spacebot federation with Flow as hub, enabling intelligent assistance across infrastructure, development, business, and client management.

**Architecture:** Single Spacebot instance with shared cortex, hub-and-spoke routing via Flow agent, per-domain autonomy policies, and adaptive escalation learning.

**Tech Stack:** Spacebot (ghcr.io/spacedriveapp/spacebot:latest), Podman, NixOS systemd, TOML configuration, Telegram Bot API

---

## Prerequisites

- Spacebot running at `/var/lib/spacebot`
- Telegram bot token configured (`8351299615:AAH8w87_rG8AM7nhV3eb70DY6IxuYSXqPSs`)
- AI Gateway accessible at `http://10.0.2.2:8080`
- Write access to `/var/lib/spacebot/config.toml`

---

## Phase 1: Core Flow Agent Deployment

### Task 1: Backup Current Configuration

**Files:**
- Read: `/var/lib/spacebot/config.toml`
- Create: `/var/lib/spacebot/config.toml.backup`

**Step 1: Create backup**

```bash
sudo cp /var/lib/spacebot/config.toml /var/lib/spacebot/config.toml.backup
```

**Step 2: Verify backup exists**

```bash
sudo ls -la /var/lib/spacebot/config.toml.backup
```
Expected: File exists with non-zero size

**Step 3: Commit backup reference**

```bash
cd /etc/nixos
git add docs/plans/2026-03-09-j-kro-agent-federation-implementation.md
git commit -m "feat: add agent federation implementation plan"
```

---

### Task 2: Write New Agent Federation Configuration

**Files:**
- Modify: `/var/lib/spacebot/config.toml`

**Step 1: Create the new configuration with all 6 agents**

Write to `/tmp/spacebot-federation-config.toml`:

```toml
[llm]
kilo_key = "secret:KILO_API_KEY"
zai_coding_plan_key = "secret:ZAI_CODING_PLAN_API_KEY"

# ============================================================================
# LLM PROVIDER - Using AI Gateway
# ============================================================================
[llm.provider.ai-gateway]
api_type = "openai_completions"
base_url = "http://10.0.2.2:8080"
api_key = "dummy-key-for-gateway"
name = "AI Gateway"

# ============================================================================
# MODEL ROUTING
# ============================================================================
[defaults.routing]
channel = "kilo/z-ai/glm-4.5-air"
worker = "kilo/z-ai/glm-4.5-air"
branch = "kilo/z-ai/glm-4.5-air"
compactor = "kilo/z-ai/glm-4.5-air"
cortex = "kilo/z-ai/glm-4.5-air"

[defaults.routing.task_overrides]
coding = "magnum-opus-35b-a3b-i1"

[defaults.opencode]
enabled = true
path = "opencode"
max_servers = 5
server_startup_timeout_secs = 30
max_restart_retries = 5

[defaults.opencode.permissions]
edit = "allow"
bash = "allow"
webfetch = "allow"

# ============================================================================
# MESSAGING PLATFORMS
# ============================================================================

[messaging.telegram]
token = "8351299615:AAH8w87_rG8AM7nhV3eb70DY6IxuYSXqPSs"

# ============================================================================
# AGENTS
# ============================================================================

# Flow - j-kro's Personal Assistant Hub
[[agents]]
id = "flow"
display_name = "Flow"
description = "j-kro's personal AI assistant and hub - coordinates all specialist agents (infra, dev, business, agency, dev-ops), learns your preferences, provides summaries and oversight. Your single point of contact for your entire operation. Routes requests to appropriate specialists and learns your escalation patterns over time."

[agents.routing]
channel = "zai-coding-plan/glm-4.5-air"
branch = "zai-coding-plan/glm-5"
worker = "zai-coding-plan/glm-4.7"
compactor = "zai-coding-plan/glm-4.7"
cortex = "zai-coding-plan/glm-5"
voice = ""
rate_limit_cooldown_secs = 15

[agents.sandbox]
mode = "disabled"
writable_paths = ["/data/@projects", "/etc/nixos"]

[agents.browser]
enabled = true
headless = true
evaluate_enabled = true
persist_session = true
close_policy = "close_browser"

[agents.coalesce]
enabled = true
debounce_ms = 1500
max_wait_ms = 5000
min_messages = 2
multi_user_only = false

# Infra - Infrastructure & Mining
[[agents]]
id = "infra"
display_name = "Infra"
description = "Manages j-kro's NixOS infrastructure, 4-host mining cluster (Zephyr=RTX 3090+3060Ti, Nexus=1xNVIDIA, Forge=2xRTX4060+2xRX5700XT, Sentry=1xAMD), deployments, and system health. Can restart services, view logs, adjust power schedules. Escalates for NixOS rebuilds and major config changes."

[agents.routing]
channel = "zai-coding-plan/glm-4.5-air"
branch = "zai-coding-plan/glm-5"
worker = "zai-coding-plan/glm-4.7"
compactor = "zai-coding-plan/glm-4.7"
cortex = "zai-coding-plan/glm-5"
voice = ""
rate_limit_cooldown_secs = 30

[agents.sandbox]
mode = "disabled"
writable_paths = ["/data/@projects", "/etc/nixos"]

[agents.browser]
enabled = true
headless = true
evaluate_enabled = true
persist_session = true
close_policy = "close_browser"

[agents.coalesce]
enabled = true
debounce_ms = 1500
max_wait_ms = 5000
min_messages = 2
multi_user_only = false

# Dev - Development Work
[[agents]]
id = "dev"
display_name = "Dev"
description = "Handles coding, debugging, code review, and feature development across all projects in /data/@projects. Can write code, run tests, commit to feature branches. Escalates for merging to main, breaking changes, and new dependencies."

[agents.routing]
channel = "zai-coding-plan/glm-4.5-air"
branch = "zai-coding-plan/glm-5"
worker = "zai-coding-plan/glm-4.7"
compactor = "zai-coding-plan/glm-4.7"
cortex = "zai-coding-plan/glm-5"
voice = ""
rate_limit_cooldown_secs = 30

[agents.sandbox]
mode = "disabled"
writable_paths = ["/data/@projects"]

[agents.browser]
enabled = true
headless = true
evaluate_enabled = true
persist_session = true
close_policy = "close_browser"

[agents.coalesce]
enabled = true
debounce_ms = 1500
max_wait_ms = 5000
min_messages = 2
multi_user_only = false

# Business - Client & Business Operations
[[agents]]
id = "business"
display_name = "Business"
description = "Manages client communications, project status tracking, billing, proposals, and business relationships. Knows each client (Robin/TrovesAndCoves, future clients), active projects, deadlines. Can reply to routine inquiries and generate invoices. Escalates for making promises and pricing changes."

[agents.routing]
channel = "zai-coding-plan/glm-4.5-air"
branch = "zai-coding-plan/glm-5"
worker = "zai-coding-plan/glm-4.7"
compactor = "zai-coding-plan/glm-4.7"
cortex = "zai-coding-plan/glm-5"
voice = ""
rate_limit_cooldown_secs = 30

[agents.sandbox]
mode = "disabled"
writable_paths = ["/data/@projects"]

[agents.browser]
enabled = true
headless = true
evaluate_enabled = true
persist_session = true
close_policy = "close_browser"

[agents.coalesce]
enabled = true
debounce_ms = 1500
max_wait_ms = 5000
min_messages = 2
multi_user_only = false

# Agency - Client Portfolio Manager
[[agents]]
id = "agency"
display_name = "Agency"
description = "Oversees all client relationships and can spawn new client-specific agents. Tracks portfolio health, deadlines, and coordinates between business needs and technical delivery. Knows each client's assigned agent (trovesandcoves for Robin). Can create new client agents and generate portfolio status reports."

[agents.routing]
channel = "zai-coding-plan/glm-4.5-air"
branch = "zai-coding-plan/glm-5"
worker = "zai-coding-plan/glm-4.7"
compactor = "zai-coding-plan/glm-4.7"
cortex = "zai-coding-plan/glm-5"
voice = ""
rate_limit_cooldown_secs = 30

[agents.sandbox]
mode = "disabled"
writable_paths = ["/data/@projects"]

[agents.browser]
enabled = true
headless = true
evaluate_enabled = true
persist_session = true
close_policy = "close_browser"

[agents.coalesce]
enabled = true
debounce_ms = 1500
max_wait_ms = 5000
min_messages = 2
multi_user_only = false

# DevOps - Deep Technical Work
[[agents]]
id = "dev-ops"
display_name = "DevOps"
description = "j-kro's deep technical work agent - infrastructure architecture, system design, complex debugging, NixOS modules, AI stack engineering (Gateway, Qwen, LM Studio). Works under j-kro's direction for architectural decisions and complex technical challenges."

[agents.routing]
channel = "zai-coding-plan/glm-4.5-air"
branch = "zai-coding-plan/glm-5"
worker = "zai-coding-plan/glm-4.7"
compactor = "zai-coding-plan/glm-4.7"
cortex = "zai-coding-plan/glm-5"
voice = ""
rate_limit_cooldown_secs = 60

[agents.sandbox]
mode = "disabled"
writable_paths = ["/data/@projects", "/etc/nixos"]

[agents.browser]
enabled = true
headless = true
evaluate_enabled = true
persist_session = true
close_policy = "close_browser"

[agents.coalesce]
enabled = true
debounce_ms = 1500
max_wait_ms = 5000
min_messages = 2
multi_user_only = false

# TrovesAndCoves - Robin's Business Assistant
[[agents]]
id = "trovesandcoves"
display_name = "TrovesAndCoves"
description = "Robin's AI assistant for managing her crystal jewelry website (trovesandcoves.com). Helps add products, update content, manage inventory, handle customer inquiries, and coordinate with j_kro for larger features. Robin is the business owner - creative, focused on showcasing crystals. Technical architect: j_kro."

[agents.routing]
channel = "zai-coding-plan/glm-4.5-air"
branch = "zai-coding-plan/glm-5"
worker = "zai-coding-plan/glm-4.7"
compactor = "zai-coding-plan/glm-4.7"
cortex = "zai-coding-plan/glm-5"
voice = ""
rate_limit_cooldown_secs = 15

[agents.sandbox]
mode = "disabled"
writable_paths = ["/data/@projects"]

[agents.browser]
enabled = true
headless = true
evaluate_enabled = true
persist_session = true
close_policy = "close_browser"

[agents.coalesce]
enabled = true
debounce_ms = 1500
max_wait_ms = 5000
min_messages = 2
multi_user_only = false

# ============================================================================
# BINDINGS
# ============================================================================

# Flow hub receives all Telegram messages
[[bindings]]
agent_id = "flow"
channel = "telegram"

# TrovesAndCoves bound to Telegram for Robin
[[bindings]]
agent_id = "trovesandcoves"
channel = "telegram"

# ============================================================================
# API SERVER
# ============================================================================
[api]
bind = "0.0.0.0"
port = 19898

# ============================================================================
# ADVANCED CONFIGURATION
# ============================================================================
[database]
path = "/data/spacebot.db"

[secrets]
path = "/data/secrets.redb"

[memory.lance]
path = "/data/lance"

[ingestion]
path = "/data/ingest"

[skills]
path = "/data/skills"
```

**Step 2: Deploy the configuration**

```bash
sudo cp /tmp/spacebot-federation-config.toml /var/lib/spacebot/config.toml
```

**Step 3: Verify the config was written**

```bash
sudo grep "^id = " /var/lib/spacebot/config.toml
```
Expected: Shows 7 agent IDs (flow, infra, dev, business, agency, dev-ops, trovesandcoves)

---

### Task 3: Restart Spacebot

**Step 1: Restart the service**

```bash
sudo systemctl restart spacebot
```

**Step 2: Wait for startup and check status**

```bash
sleep 5 && sudo systemctl status spacebot --no-pager | head -15
```
Expected: `Active: active (running)`

**Step 3: Verify all agents are running**

```bash
sudo journalctl -u spacebot --no-pager --since "1 minute ago" | grep "agent_id="
```
Expected: Logs showing multiple agent_ids (flow, infra, dev, business, etc.)

**Step 4: Check for cortex initialization**

```bash
sudo journalctl -u spacebot --no-pager --since "1 minute ago" | grep "cortex.*loop started"
```
Expected: 7 cortex loops started (one per agent)

---

### Task 4: Verify Agent Configuration

**Step 1: Test Flow agent responds**

```bash
echo "Testing agent configuration" | sudo tee /tmp/test-spacebot.txt
```

**Step 2: Check Web UI is accessible**

```bash
curl -s http://127.0.0.1:19898 | head -10
```
Expected: HTML response (Spacebot web UI)

**Step 3: Verify Telegram connectivity**

```bash
sudo journalctl -u spacebot --no-pager --since "2 minutes ago" | grep -i "telegram\|polling"
```
Expected: Telegram polling logs or connection established

---

## Phase 2: Testing & Verification

### Task 5: Test Hub Routing

**Step 1: Send test message via Telegram Web UI**

Open http://127.0.0.1:19898 in browser

**Step 2: Send message to Flow**

In the Web UI, send: "Hello Flow, what agents are available?"

**Step 3: Verify response**

Expected: Flow responds listing available agents

**Step 4: Log the test**

```bash
sudo journalctl -u spacebot --since "1 minute ago" | tail -20
```

---

### Task 6: Test Direct Addressing

**Step 1: Send direct message to infra**

Via Telegram or Web UI: "@infra what's the status of the mining cluster?"

**Step 2: Verify infra agent responded**

Expected: Response about mining cluster status

**Step 3: Verify logs show routing**

```bash
sudo journalctl -u spacebot --since "2 minutes ago" | grep "infra"
```

---

### Task 7: Cross-Agent Context Test

**Step 1: Ask Flow about cross-agent awareness**

Via Telegram or Web UI: "Flow, do you know about Robin and trovesandcoves?"

**Step 2: Verify response**

Expected: Flow knows about Robin as client and trovesandcoves agent

---

## Phase 3: Escalation Policy Setup

### Task 8: Create Initial Escalation Policy

**Files:**
- Create: `/var/lib/spacebot/memories/escalation-policy.json`

**Step 1: Create memories directory**

```bash
sudo mkdir -p /var/lib/spacebot/memories
```

**Step 2: Write initial escalation policy**

```bash
sudo tee /var/lib/spacebot/memories/escalation-policy.json > /dev/null <<'EOF'
{
  "version": "1.0",
  "last_updated": "2026-03-09",
  "user": "j-kro",
  "tiers": {
    "silent": {
      "description": "Handle silently, log for summary",
      "examples": [
        "Service restarts succeeded",
        "Routine client inquiries answered",
        "Tests passed",
        "Feature branch committed",
        "Mining pool switch completed"
      ]
    },
    "notify": {
      "description": "Send notification, don't interrupt",
      "examples": [
        "New client inquiry received",
        "Deployment completed",
        "Code review has suggestions",
        "Mining hashrate dropped 10%",
        "Invoice generated"
      ]
    },
    "decision": {
      "description": "Wait for user input",
      "examples": [
        "NixOS rebuild required",
        "Merging to main branch",
        "Client requests feature work",
        "Security patch needs attention",
        "Spending money required"
      ]
    },
    "interrupt": {
      "description": "Immediate alert regardless of context",
      "examples": [
        "Production site down",
        "Security incident detected",
        "Client complaint/escalation",
        "Mining rig offline > 30min",
        "Cluster resource exhausted"
      ]
    }
  },
  "learning": {
    "mode": "conservative",
    "signals_tracked": [
      "response_time",
      "user_feedback",
      "time_of_day",
      "current_activity"
    ]
  }
}
EOF
```

**Step 3: Verify file was created**

```bash
sudo cat /var/lib/spacebot/memories/escalation-policy.json
```
Expected: Valid JSON with escalation tiers

---

### Task 9: Create Client Preferences Template

**Files:**
- Create: `/var/lib/spacebot/memories/client-preferences.json`

**Step 1: Write client preferences template**

```bash
sudo tee /var/lib/spacebot/memories/client-preferences.json > /dev/null <<'EOF'
{
  "version": "1.0",
  "last_updated": "2026-03-09",
  "clients": {
    "trovesandcoves": {
      "name": "Robin",
      "business": "TrovesAndCoves crystal jewelry",
      "website": "trovesandcoves.com",
      "agent": "trovesandcoves",
      "contact": {
        "telegram": "pending",
        "phone": "+1 204 228 3562"
      },
      "preferences": {
        "communication_style": "friendly but professional",
        "update_frequency": "as needed for business",
        "deployment_window": "thursday mornings preferred",
        "technical_contact": "j_kro for infrastructure"
      },
      "status": "active"
    }
  }
}
EOF
```

**Step 2: Verify file was created**

```bash
sudo cat /var/lib/spacebot/memories/client-preferences.json
```

---

## Phase 4: Documentation & Handoff

### Task 10: Update NixOS Configuration Reference

**Files:**
- Modify: `/etc/nixos/docs/SPACEBOT_SETUP_GUIDE.md`

**Step 1: Add agent federation section to docs**

```bash
sudo tee -a /etc/nixos/docs/SPACEBOT_SETUP_GUIDE.md > /dev/null <<'EOF'

## Agent Federation (j-kro's Personal Setup)

As of 2026-03-09, j-kro's Spacebot instance runs a 7-agent federation:

1. **Flow** (hub) - Personal assistant, coordinates all agents
2. **Infra** - NixOS, mining cluster, deployments
3. **Dev** - Coding, debugging, feature development
4. **Business** - Client comms, billing, project status
5. **Agency** - Client portfolio manager
6. **DevOps** - Deep technical/architectural work
7. **TrovesAndCoves** - Robin's business assistant

All agents accessible via Telegram bot or Web UI at http://localhost:19898.
Default routing goes through Flow; use @agent_name for direct addressing.
EOF
```

---

### Task 11: Final Verification

**Step 1: Check all agents in logs**

```bash
sudo journalctl -u spacebot --no-pager -n 100 | grep -oP 'agent_id="\K[^"]+' | sort -u
```
Expected: Lists all 7 agent IDs

**Step 2: Verify Web UI shows all agents**

Open http://127.0.0.1:19898
Navigate to Agents section
Expected: All 7 agents listed

**Step 3: Commit final state**

```bash
cd /etc/nixos
git add docs/plans/2026-03-09-j-kro-agent-federation-implementation.md
git add docs/SPACEBOT_SETUP_GUIDE.md
git commit -m "feat: complete agent federation deployment

- Deployed 7-agent federation with Flow as hub
- Configured per-domain autonomy policies
- Set up escalation learning framework
- Added client preferences for Robin/TrovesAndCoves

All agents verified running and accessible via Telegram + Web UI."
```

---

## Success Criteria

| Criterion | Command | Expected Result |
|-----------|---------|-----------------|
| 7 agents running | `sudo journalctl -u spacebot | grep agent_id= | sort -u | wc -l` | 7 |
| Flow responds to messages | Send via Web UI | Response |
| Direct addressing works | Send "@infra status" | Infra responds |
| Telegram connected | `sudo journalctl -u spacebot | grep telegram` | No errors |
| Config backup exists | `ls -la /var/lib/spacebot/config.toml.backup` | File exists |
| Escalation policy exists | `cat /var/lib/spacebot/memories/escalation-policy.json` | Valid JSON |

---

## Troubleshooting

**Spacebot won't start after config update:**
```bash
# Check config syntax
sudo podman run --rm ghcr.io/spacedriveapp/spacebot:latest --validate-config /data/config.toml

# Restore backup if needed
sudo cp /var/lib/spacebot/config.toml.backup /var/lib/spacebot/config.toml
sudo systemctl restart spacebot
```

**Agent not responding:**
```bash
# Check logs for specific agent
sudo journalctl -u spacebot | grep "agent_id=<name>"

# Restart spacebot
sudo systemctl restart spacebot
```

**Telegram not connected:**
```bash
# Verify token in config
sudo grep "messaging.telegram" /var/lib/spacebot/config.toml -A 2

# Check logs for Telegram errors
sudo journalctl -u spacebot | grep -i telegram
```

---

## Next Steps (Post-Implementation)

1. **Train Flow**: Use for a week, provide feedback on escalation decisions
2. **Add Skills**: Install domain-specific skills via Spacebot's skills system
3. **Client Expansion**: Use agency agent to spawn new client agents
4. **Monitoring**: Set up metrics collection for agent performance
5. **Refinement**: Adjust autonomy policies based on usage patterns
