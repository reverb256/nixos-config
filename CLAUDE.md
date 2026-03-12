# NixOS Configuration - Claude Code Agent Patterns

## Purpose
This document contains Claude Code-specific patterns and workflows for this NixOS configuration. It extends the universal guidelines in `AGENTS.md` with Claude Code features like Serena semantic tools and async agent launching.

**Read AGENTS.md first** for universal cluster patterns, build commands, and deployment workflows.

---

## ⚠️ CRITICAL: Agent Safety Constraints

**READ THIS before making any changes to shared modules or critical infrastructure!**

### 🚨 Forbidden Operations (Will Break Cluster)

**NEVER use direct assignment on extensible options in shared modules:**

❌ **WRONG - This REPLACES node configs:**
```nix
networking.firewall.allowedTCPPorts = [22 53 6443];
users.users.j_kro.extraGroups = ["wheel"];
networking.searchDomains = ["lan" "cluster.local"];
```

✅ **CORRECT - This MERGES with node configs:**
```nix
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22 53 6443];
users.users.j_kro.extraGroups = lib.mkOptionDefault ["wheel"];
networking.searchDomains = lib.mkOptionDefault ["lan" "cluster.local"];
```

### 🔒 Critical Infrastructure Rules

1. **SSH/Connectivity Changes**
   - **MUST** preserve SSH port 22 in all firewall configs
   - **MUST** test on at least 2 nodes before committing
   - **FORBIDDEN** to deploy to all nodes simultaneously

2. **Shared Module Changes**
   - **MUST** use `lib.mkOptionDefault` for list/array options
   - **MUST** test on nodes with custom configs (not just zephyr)
   - **FORBIDDEN** to assume nodes have identical configurations

3. **Firewall/Network Changes**
   - **MUST** verify: `iptables -L | grep dpt:22` after changes
   - **MUST** use incremental rollout: test → verify → deploy
   - **FORBIDDEN** to bypass pre-commit checks

### 📋 Mandatory Testing Checklist

Before committing changes to:
- `modules/networking/*` → Test SSH on zephyr AND nexus
- `modules/system/ssh.nix` → Test SSH on all 4 nodes
- `modules/system/users.nix` → Test login on all 4 nodes
- `modules/default.nix` → Test entire cluster

### 🛑 Stop Work Immediately If

- SSH breaks on any node → Document incident, wait for human
- Login breaks on any node → Document incident, wait for human
- Multiple nodes affected → **STOP ALL WORK**, create urgent task

### 📝 Incident Response Process

If you break something:
1. **STOP** making changes immediately
2. **DOCUMENT** in `/etc/nixos/AGENT_INCIDENT_REPORT.md`:
   ```markdown
   # Incident Report - [DATE]
   ## What Broke
   ## Changes Made
   ## Affected Nodes
   ## Root Cause
   ## Proposed Fix
   ```
3. **WAIT** for human intervention
4. **DO NOT** make further autonomous changes

### 🎯 Design Principles for Agents

**Rule 1: Extensibility Over Purity**
- If nodes might extend an option, use `mkOptionDefault`
- If option is hard requirement, direct assignment is OK
- When in doubt, use `mkOptionDefault`

**Rule 2: Test Before Deploy**
- Test on 1 node with custom config (nexus or forge)
- Verify critical services (SSH, login, networking)
- Only then commit for wider deployment

**Rule 3: Preserve Critical Ports**
- SSH (22) MUST always be open
- DNS (53) MUST always be open
- Kubernetes API (6443) MUST always be open on cluster nodes

**Rule 4: Incremental Rollout**
- Never deploy to all 4 nodes at once
- Use: `just switch <node>` for each node individually
- Monitor for issues before proceeding to next node

### 📖 Learn From Mistakes

**What Went Wrong (2026-03-12):**
- Created `cluster-networking.nix` with direct assignment
- Used `allowedTCPPorts = [22 53 6443]` instead of `lib.mkOptionDefault [22 53 6443]`
- Deployed to all nodes without testing
- Result: Nexus/sentry configs REPLACED cluster defaults, removing SSH port 22
- Impact: SSH broken on nexus and sentry, required physical console access to fix

**The Fix:**
Changed to `lib.mkOptionDefault` which provides defaults that can be extended/merged instead of replaced.

**Prevention:**
- Pre-commit hooks to block dangerous patterns
- Mandatory testing on nodes with custom configs
- Documentation of safe patterns (this section)

---

## Quick Start

1. Read `AGENTS.md` for universal cluster patterns
2. **Use Serena semantic tools for ALL code understanding** (see section below)
3. Launch async agents for parallel independent tasks
4. Always use `just` commands for CI/CD integration


---



---

## When to Use Serena Semantic Tools

**Use Serena for ALL complex code understanding tasks:**

### ✅ Use Serena When:
- **Understanding module structure** - `get_symbols_overview()` for file architecture
- **Finding symbol definitions** - `find_symbol()` to locate functions, classes, options
- **Tracing references** - `find_referencing_symbols()` to see where symbols are used
- **Multi-step refactoring** - Symbol-aware edits preserve structure
- **Cross-file analysis** - Understanding relationships between modules
- **Large codebase navigation** - Quickly locate patterns without reading entire files

### ❌ Use Standard Tools When:
- **Simple file reading** - `Read` for single files you already know
- **Basic pattern matching** - `Grep` for simple text searches
- **File discovery** - `Glob` for finding files by pattern
- **Quick fixes** - `Edit` for simple, localized changes

### Key Principle:
**Serena is DEFAULT for code understanding.** Only use Read/Grep/Glob when you have a clear, simple target. Serena's semantic understanding prevents errors in complex NixOS module structures.

---


## Working with NixOS Modules Safely

### ⚠️ Module System Safety Rules

**CRITICAL: Understanding NixOS Option Semantics**

In NixOS modules, how you set options determines whether they merge or replace:

| Syntax | Behavior | Use When |
|--------|----------|----------|
| `opt = value` | **REPLACES** any previous value | Hard requirements, non-extensible options |
| `opt = lib.mkOptionDefault value` | **MERGES** - provides default that can be extended | Extensible options that nodes might customize |
| `opt = lib.mkMerge [list]` | **MERGES** multiple definitions | Combining multiple sources explicitly |

### 🚨 Dangerous Patterns (FORBIDDEN)

**❌ NEVER do this in shared modules:**
```nix
# DANGER: Direct assignment on extensible options!
networking.firewall.allowedTCPPorts = [22 53];
users.users.j_kro.extraGroups = ["wheel"];
environment.systemPackages = [pkgs.somePackage];
```

**Why this breaks things:**
- When a node config sets `networking.firewall.allowedTCPPorts = [10250]`
- It **REPLACES** the module's `[22 53]` entirely
- Result: Only port 10250 is open, **SSH (port 22) is BLOCKED**

### ✅ Safe Patterns (REQUIRED)

**✅ ALWAYS do this in shared modules:**
```nix
# SAFE: Mergeable defaults
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
  22    # SSH
  53    # DNS
];
users.users.j_kro.extraGroups = lib.mkOptionDefault ["wheel"];
environment.systemPackages = lib.mkOptionDefault [pkgs.somePackage];
```

**Why this works:**
- Module provides defaults that nodes can extend
- When node config sets `networking.firewall.allowedTCPPorts = [10250]`
- It **MERGES** with defaults: `[22 53] ++ [10250]`
- Result: All ports present, **SSH still works**

### 📊 Decision Tree for Module Changes

When creating or modifying shared modules, ask:

```
Is this option extensible (might nodes want to customize)?
├─ YES → Use lib.mkOptionDefault
└─ NO  → Direct assignment OK
```

**Examples:**

```nix
# Extensible: Nodes add custom firewall ports
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22 53];

# Not extensible: Boolean switches
networking.firewall.enable = true;  # Direct assignment OK

# Extensible: Nodes add custom packages
environment.systemPackages = lib.mkOptionDefault [pkgs.curl];

# Not extensible: Hard requirements
time.timeZone = "America/Chicago";  # Direct assignment OK
```

### 🔍 Module Creation Checklist

Before creating a shared module:

- [ ] Does this module use `mkOptionDefault` for list options?
- [ ] Have I tested this on at least 2 different node types?
- [ ] Does this preserve SSH port 22?
- [ ] Can nodes extend this without breaking base functionality?
- [ ] Did I document merge/replace behavior in comments?

---


## Claude Code-Specific Features

### Serena Semantic Tools
Powerful code understanding for navigating NixOS configurations:

**find_symbol**: Locate symbols by name
```
find_symbol(name_path_pattern="ClusterStorage", relative_path="...")
```

**find_referencing_symbols**: Find all references
```
find_referencing_symbols(name_path="ensureStorageMounted", ...)
```

**get_symbols_overview**: Quick file structure
```
get_symbols_overview(relative_path="hosts/zephyr/...", depth=1)
```

### Async Agent Launching
Launch multiple agents for parallel independent tasks:
```python
Agent(description="Analyze storage", prompt="...")
Agent(description="Review GPU setup", prompt="...")
```

### Claude MCP Integration
Always include Accept header for ZAI MCP:
```bash
curl -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $(cat /run/agenix/zai-api-key)" \
  https://api.z.ai/api/mcp/web_search_prime/mcp
```

See: `.claude/hookify.warn-mcp-accept-headers.local.md`

---



---


---


---



## See Also

### Universal Documentation
- **AGENTS.md**: Universal patterns for all agents
  - Build & test commands (just commands)
  - Deployment workflows (Colmena, multi-host)
  - Kubernetes migration (9-week plan)
  - MCP integration (protocol, troubleshooting)

- **DOCUMENTATION_INDEX.md**: Comprehensive documentation index
- **ROADMAP.md**: Complete Kubernetes migration plan

### Cluster Information
- **Hosts**: Zephyr (control plane), Nexus (storage), Forge (GPU), Sentry (monitoring)
- **Resources**: 78 cores, 123GB RAM, 7 GPUs (5x NVIDIA + 2x AMD), 8.4TB storage
- **Architecture**: NixOS flakes, profile-based, declarative configuration

### Workflow Commands
```bash
just test              # Verify configuration
just switch            # Apply to local host
just deploy            # Deploy to all hosts
# just sync              # Sync all nodes to current branch (DEPRECATED: Colmena handles this automatically)
```

---

## Security

### Documentation
- `docs/security/SECURITY_AUDIT_REPORT.md` - Comprehensive security audit
- `docs/security/HARDENING_SUMMARY.md` - Implementation status
- `docs/kubernetes/network-policies/` - Network policy templates
- `docs/security/secrets-rotation.md` - Rotation procedures
- `docs/security/emergency-access.md` - Emergency procedures

### Commands
```bash
just scan-containers  # Scan running containers for vulnerabilities
just scan-image IMAGE # Scan specific image
```

---

**Version**: 2.0 | **Updated**: 2026-03-12
**Changes**: Added critical agent safety constraints and module design patterns
**Generated from**: `/etc/nixos/docs/templates/base-template.md.j2`

