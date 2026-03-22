---
name: knowledge-fabric
description: ⚠️ **CRITICAL: This skill uses ONLY MCP tools - NO API calls, NO gateway, NO HTTP requests.** Execute MCP tools directly: search_code, search_research, search_github, web_search, search_stackoverflow, etc. DO NOT call any APIs, gateways, or HTTP endpoints. DO NOT use curl, wget, or any network requests. Use ONLY MCP tool calls.
---

# ⚠️ KNOWLEDGE FABRIC - MCP-ONLY IMPLEMENTATION

## 🚨 CRITICAL RULES - READ FIRST

**WHAT THIS SKILL DOES:**
- ✅ Uses **MCP tools ONLY** (search_code, search_research, web_search, etc.)
- ✅ Executes **parallel MCP tool calls**
- ✅ Aggregates results from MCP tools

**WHAT THIS SKILL DOES NOT DO:**
- ❌ **NO API calls** - Do NOT call http://127.0.0.1:8080 or any HTTP endpoint
- ❌ **NO gateway calls** - Do NOT use the AI Inference Gateway
- ❌ **NO curl/wget** - Do NOT make any HTTP requests
- ❌ **NO Kubernetes API** - Do NOT call /api, /apis, or any K8s endpoints
- ❌ **NO subprocess execution** - Do NOT run external commands

## 🎯 EXACT WORKFLOW (Follow These Steps Precisely)

### Step 1: Analyze User Query
Read the user's query and classify it:
- **CODE**: Programming, functions, APIs, debugging
- **RESEARCH**: Academic papers, documentation, deep analysis
- **DEVOPS**: Docker, Kubernetes, deployment, infrastructure
- **GENERAL**: Everything else

### Step 2: Select MCP Tools (Choose from THIS LIST ONLY)

**Available MCP Tools (USE THESE):**
- `search_code` - Code search (GitHub, StackOverflow, GitLab)
- `search_research` - Academic papers (Google Scholar, arXiv)
- `search_devops` - DevOps content (Docker Hub, Kubernetes docs)
- `search_data` - ML/DS content (HuggingFace, Kaggle)
- `search_github` - GitHub repositories
- `search_stackoverflow` - StackOverflow Q&A
- `search_nixos_options` - NixOS configuration options
- `web_search` - General web search
- `ping_searxng` - Test SearXNG connectivity

**Tool Selection Guide:**
```
IF query contains: "code", "function", "API", "debug", "implement"
  THEN use: search_code, search_github, search_stackoverflow

IF query contains: "paper", "research", "academic", "scholar"
  THEN use: search_research, web_search

IF query contains: "docker", "kubernetes", "deploy", "infrastructure"
  THEN use: search_devops, search_github

IF query contains: "nixos", "configuration", "flake", "module"
  THEN use: search_nixos_options, search_code, web_search

IF query contains: "machine learning", "model", "dataset", "training"
  THEN use: search_data, search_research

ELSE:
  use: web_search, search_code
```

### Step 3: Execute MCP Tools (CALL MCP TOOLS DIRECTLY)

**IMPORTANT:** Call MCP tools DIRECTLY by their tool name (mcp__gateway__*), NOT via the Skill tool.

**Example execution:**
```
1. Call mcp__gateway__search_code with query parameter
2. Call mcp__gateway__search_github with query parameter
3. Call mcp__gateway__web_search with query parameter
4. Wait for ALL tools to complete
5. Collect results from all tools
```

**DO NOT:**
- ❌ Make HTTP requests
- ❌ Call APIs directly
- ❌ Use subprocess/bash to run curl
- ❌ Call the gateway at http://127.0.0.1:8080
- ❌ Wrap MCP tools in Skill() calls - they are NOT skills

### Step 4: Aggregate Results

**Collect results from each MCP tool:**
```markdown
## Results from search_code
- [Result 1]
- [Result 2]
- [Result 3]

## Results from search_github
- [Result 1]
- [Result 2]

## Results from web_search
- [Result 1]
- [Result 2]
```

### Step 5: Present Findings

Format your response as:
```markdown
# Knowledge Fabric Results

## Query Analysis
- **Intent**: [CODE/RESEARCH/DEVOPS/GENERAL]
- **Tools Used**: [list of MCP tools called]

## Top Findings

### 1. [Title from result]
**Source**: [which MCP tool found it]
**URL**: [link]
**Snippet**: [relevant excerpt]

### 2. [Next result]
...

## Summary
[2-3 sentence synthesis of key findings]
```

## 🚫 FORBIDDEN OPERATIONS

**NEVER DO THESE (they will FAIL):**

```bash
# ❌ DO NOT call the gateway
curl http://127.0.0.1:8080/v1/chat/completions

# ❌ DO NOT call Kubernetes API
curl http://127.0.0.1:6443/api
curl /apis?timeout=32s

# ❌ DO NOT use subprocess
import subprocess
subprocess.run(["curl", "http://127.0.0.1:8080"])

# ❌ DO NOT make HTTP requests
requests.get("http://127.0.0.1:8080")
```

**IF YOU ARE TEMPTED TO DO ANY OF THE ABOVE:**
1. **STOP**
2. **READ THIS FILE AGAIN**
3. **USE MCP TOOLS INSTEAD**

## ✅ CORRECT OPERATIONS

**ONLY DO THESE:**

```python
# ✅ Call MCP tools DIRECTLY (not via Skill tool)
mcp__gateway__search_code(query=user_query, max_results=10)
mcp__gateway__search_github(query=user_query, max_results=10)
mcp__gateway__web_search(query=user_query, max_results=10)

# ✅ Wait for results
# ✅ Aggregate results
# ✅ Present findings
```

**Tool Names (Use Exactly These):**
- `mcp__gateway__search_code`
- `mcp__gateway__search_research`
- `mcp__gateway__search_devops`
- `mcp__gateway__search_data`
- `mcp__gateway__search_github`
- `mcp__gateway__search_nixos_options`
- `mcp__gateway__search_mdn`
- `mcp__gateway__search_stackoverflow`
- `mcp__gateway__search_reddit`
- `mcp__gateway__web_search`
- `mcp__gateway__search_stats`
- `mcp__gateway__clear_search_cache`
- `mcp__gateway__ping_searxng`

## 🔍 Troubleshooting

**If MCP tools don't work:**
1. Check settings.json has `enabledMcpjsonServers` list with all required servers
2. Verify `.mcp.json` exists and has the MCP server configurations
3. Check if MCP server is running: `mcp-gateway-bridge --help`
4. Try individual tools first: `search_code` alone, then `web_search` alone
5. For SearXNG: Verify K8s service is running (`kubectl get svc -n search searxng`)

**Common Issues:**
- **"Failed to communicate with local MCP server searxng"**:
  - Check if `searxng` is in `enabledMcpjsonServers` list
  - Verify `.mcp.json` has searxng configuration with K8s URL (http://10.0.0.102:8080)
  - Ensure SearXNG pods are running: `kubectl get pods -n search`

**If you get an error about APIs:**
1. You're doing something WRONG
2. Re-read this file
3. Use MCP tools ONLY

## 📋 Example Session

**User:** "How do I configure NixOS flakes for colmena?"

**Agent execution:**
```
Step 1: Classify as CODE + NIXOS intent
Step 2: Select tools: search_nixos_options, search_code, web_search
Step 3: Execute tools:
  - mcp__gateway__search_nixos_options(query="flakes colmena configuration")
  - mcp__gateway__search_code(query="nixos flake colmena")
  - mcp__gateway__web_search(query="nixos flakes colmena tutorial")
Step 4: Aggregate results
Step 5: Present findings with code examples and links
```

**Total time:** ~5-10 seconds (NO 30-second waits, NO thinking mode)

## 🎓 Key Points

1. **MCP TOOLS ONLY** - Nothing else
2. **CALL MCP TOOLS DIRECTLY** - Use `mcp__gateway__*` tool names, NOT Skill tool
3. **PARALLEL EXECUTION** - Call multiple tools simultaneously
4. **FAST RESPONSES** - No waiting for LLMs or APIs
5. **DIRECT RESULTS** - MCP tools return search results directly

## 🚀 Why This Works

**Old approach (BROKEN):**
- Call gateway → Gateway calls LLM → LLM thinks for 30s → Gateway searches → Results
- Total time: 30-60 seconds
- Failure rate: High (thinking mode, gateway errors)

**New approach (WORKING):**
- Call MCP tools directly → Tools search → Results
- Total time: 5-10 seconds
- Failure rate: Low (direct tool access)

---

**Last Updated:** 2026-03-22
**Version:** 2.2 (FIXED: Call MCP tools directly, NOT via Skill tool)
**Status:** ✅ Working when agents follow instructions correctly
**Known Issues:**
- Agents may ignore instructions and call APIs - this is a agent execution problem, not a skill problem
- MCP servers must be enabled in `enabledMcpjsonServers` list in settings.json
- SearXNG uses K8s service (http://10.0.0.102:8080) - must be accessible
- **CRITICAL**: MCP tools must be called DIRECTLY (e.g., `mcp__gateway__search_code`), NOT via Skill tool wrapper
