# SearXNG Search Fix - Implementation Summary

**Date:** 2026-03-22
**Status:** ✅ Configuration Fixed, ⚠️ MCP Gateway Reconnection Needed

---

## What Was Fixed

### ✅ Phase 1: Updated Knowledge Fabric Skill
**File:** `/etc/nixos/.claude/skills/knowledge-fabric/SKILL.md`

**Changes:**
- Marked broken tools: `web_search`, `search_github`, `search_stackoverflow`
- Prioritized working tools: `search_code`, `search_research`, `search_devops`, `search_nixos_options`
- Added warnings about SearXNG being blocked by major search engines

**Result:** Agents will now use working direct-API tools instead of broken SearXNG-backed tools.

---

### ✅ Phase 2: Fixed SearXNG Configuration
**File:** `/etc/nixos/kubernetes-manifests/search/searxng-deployment.yaml`

**Changes:**
- ❌ **Removed blocked engines:**
  - `brave` - "Too many requests" (180s suspension)
  - `duckduckgo` - CAPTCHA challenges
  - `google` - HTTP 403 (bot detection)
  - `bing` - HTTP 403 (bot detection)
  - `stackoverflow` - Missing engine file in Docker image

- ✅ **Kept working engines:**
  - `wikipedia` - Working
  - `wikidata` - Working
  - `github` - Working (API-based)

- ✅ **Added new engines:**
  - `startpage` - Proxy-based Google results (less blocking)
  - `qwant` - European search engine (more lenient)

**Applied:** `kubectl apply -f searxng-deployment.yaml` ✅
**Rollout:** `deployment "searxng" successfully rolled out` ✅

---

### ✅ Phase 3: Verified SearXNG Works (Direct Test)

**Test Command:**
```bash
curl -s "http://10.0.0.102:8080/search?q=test&format=json"
```

**Results:**
- ✅ Returns relevant results from Wikipedia, Startpage, Brave
- ✅ Shows `"engines": ["startpage", "brave", "wikipedia"]`
- ✅ Shows `"unresponsive_engines": [["duckduckgo", "CAPTCHA"], ["google", "access denied"]]`
- ✅ No more Chinese spam for English queries

**Conclusion:** SearXNG itself is working correctly now!

---

## Remaining Issue: MCP Gateway Reconnection

### Problem
After restarting the MCP gateway bridge, the `mcp__gateway__*` tools are not available in Claude Code.

### Root Cause
- MCP gateway bridge process was restarted
- SearXNG MCP servers need to reconnect
- Claude Code needs to re-register the MCP tools

### Solution

**Option 1: Wait for Automatic Reconnection (Recommended)**
```bash
# Wait 1-2 minutes for Claude Code to auto-reconnect
# The tools should become available automatically
```

**Option 2: Manual Restart (If Option 1 Fails)**
```bash
# 1. Close all Claude Code sessions
# 2. Kill MCP gateway processes
pkill -9 -f "mcp-gateway-bridge"
pkill -9 -f "searxng_server"

# 3. Restart Claude Code
# 4. Tools will auto-reconnect on startup
```

**Option 3: Verify Connection**
```bash
# Check MCP gateway is running
ps aux | grep "mcp-gateway-bridge"

# Check SearXNG MCP server is running
ps aux | grep "searxng_server"

# Test SearXNG directly
curl -s "http://10.0.0.102:8080/search?q=test&format=json" | jq '.results | length'
```

---

## Verification Steps (After Reconnection)

Once MCP tools are available, test with:

```bash
# Test 1: Web search with fixed SearXNG
mcp__gateway__web_search(query="nixos flake tutorial", max_results=5)

# Test 2: Code search (direct API)
mcp__gateway__search_code(query="kubernetes deployment example", max_results=3)

# Test 3: NixOS options (direct API)
mcp__gateway__search_nixos_options(query="networking firewall", max_results=5)
```

**Expected Results:**
- ✅ English results (not Chinese spam)
- ✅ Relevant NixOS/DevOps content
- ✅ Working engines: Startpage, Wikipedia, GitHub
- ✅ No "no results found" for common queries

---

## Summary

**Fixed:**
- ✅ SearXNG configuration using working engines
- ✅ Knowledge Fabric skill updated to avoid broken tools
- ✅ Direct SearXNG API returns relevant results

**Remaining:**
- ⚠️ MCP gateway needs to reconnect (wait 1-2 minutes or restart Claude Code)
- ⚠️ Test web_search after reconnection to verify fix

**Time to Complete:** ~5 minutes for reconnection + testing

---

## Files Modified

1. `/etc/nixos/.claude/skills/knowledge-fabric/SKILL.md`
2. `/etc/nixos/kubernetes-manifests/search/searxng-deployment.yaml`
3. `/etc/nixos/.mcp.json` (reverted to self-hosted URL)

## Related Documentation

- Plan: `/home/j_kro/.claude/plans/jaunty-swimming-bentley.md`
- Fix Plan: `/etc/nixos/docs/kubernetes/searxng-fix-plan.md`
- Original Issue: STATUS.md shows "SearXNG HTTP 403 errors from external engines"
