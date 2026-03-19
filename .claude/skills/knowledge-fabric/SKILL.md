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

### Step 3: Execute MCP Tools (USE SKILL TOOL TO CALL MCP TOOLS)

**IMPORTANT:** Use the **Skill tool** to invoke MCP tools, then wait for results.

**Example execution:**
```
1. Invoke Skill tool with: "search_code" + user query
2. Invoke Skill tool with: "search_github" + user query
3. Invoke Skill tool with: "web_search" + user query
4. Wait for ALL tools to complete
5. Collect results from all tools
```

**DO NOT:**
- ❌ Make HTTP requests
- ❌ Call APIs directly
- ❌ Use subprocess/bash to run curl
- ❌ Call the gateway at http://127.0.0.1:8080

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
# ✅ Use MCP tools via Skill tool
Skill(tool="search_code", args={"query": user_query})
Skill(tool="search_github", args={"query": user_query})
Skill(tool="web_search", args={"query": user_query})

# ✅ Wait for results
# ✅ Aggregate results
# ✅ Present findings
```

## 🔍 Troubleshooting

**If MCP tools don't work:**
1. Check if MCP server is running: `mcp-gateway-bridge --help`
2. Check settings.json has MCP servers configured
3. Try individual tools first: `search_code` alone, then `web_search` alone

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
  - Skill("search_nixos_options", "flakes colmena configuration")
  - Skill("search_code", "nixos flake colmena")
  - Skill("web_search", "nixos flakes colmena tutorial")
Step 4: Aggregate results
Step 5: Present findings with code examples and links
```

**Total time:** ~5-10 seconds (NO 30-second waits, NO thinking mode)

## 🎓 Key Points

1. **MCP TOOLS ONLY** - Nothing else
2. **NO HTTP REQUESTS** - Use Skill tool to call MCP
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

**Last Updated:** 2026-03-19
**Version:** 2.0 (MCP-ONLY)
**Status:** ✅ Working when agents follow instructions correctly
**Known Issues:** Agents may ignore instructions and call APIs - this is a agent execution problem, not a skill problem.
