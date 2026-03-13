# NixOS Configuration - Claude Code Agent Patterns

## Purpose

Claude Code-specific patterns for this NixOS configuration. Extends @AGENTS.md with Serena semantic tools and async agent launching.

**Read @AGENTS.md first** for universal cluster patterns, build commands, and deployment workflows.

---

## Critical Safety Constraints

### Module System: mkOptionDefault Required

In shared modules, use `lib.mkOptionDefault` for extensible options:

```nix
# ❌ WRONG - REPLACES node configs
networking.firewall.allowedTCPPorts = [22 53 6443];

# ✅ CORRECT - MERGES with node configs
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22 53 6443];
```

**Why:** Direct assignment prevents nodes from extending the option, breaking SSH and other critical services.

### Build Commands: Use Justfile Only

```bash
# ✅ Safe - idempotent with auto-cleanup
just switch
just deploy
just test

# ❌ Forbidden - causes 30-60 minute hangs
colmena apply --on zephyr
nix build .#nixosConfigurations.zephyr.config.system.build.toplevel
```

**Why:** Justfile commands kill conflicting processes and clear locks. Direct colmena/nix-build commands do not.

### Testing Before Deployment

- `modules/networking/*` → Test SSH on zephyr AND nexus
- `modules/system/ssh.nix` → Test SSH on all 4 nodes
- `modules/system/users.nix` → Test login on all 4 nodes
- `modules/default.nix` → Test entire cluster

### Stop Work Immediately If

- SSH breaks on any node → Document incident, wait for human
- Login breaks on any node → Document incident, wait for human
- Multiple nodes affected → STOP ALL WORK, create urgent task

---

## Code Style

- **2-space indentation**, trailing semicolons
- **kebab-case** for files and modules
- **Line length**: 80-100 chars (soft limit 120)
- Use `lib.mkOptionDefault` for extensible options in shared modules

---

## Workflow

### Standard Development Flow

1. Make changes
2. `git add` new files (Nix only packages git-tracked files!)
3. `git commit`
4. `just test` (verifies configuration)
5. `just deploy` (applies to all hosts via Colmena)

### When to Use Serena Semantic Tools

**Use Serena for:**
- Understanding module structure (`get_symbols_overview()`)
- Finding symbol definitions (`find_symbol()`)
- Tracing references (`find_referencing_symbols()`)
- Multi-step refactoring or cross-file analysis

**Use standard tools for:**
- Simple file reading (`Read`)
- Basic pattern matching (`Grep`)
- File discovery (`Glob`)

---

## Project Structure

```
/etc/nixos/
├── flake.nix              # Flake inputs/outputs
├── hosts/                 # Per-host configs
├── modules/               # Reusable modules
│   ├── profiles/          # Profile-based configs
│   └── system/            # System-level modules
├── justfile               # CI/CD commands
├── AGENTS.md              # Universal patterns
└── CLAUDE.md              # This file
```

---

## See Also

- **@AGENTS.md**: Universal patterns for all agents
- **@DOCUMENTATION_INDEX.md**: Comprehensive documentation index
- **@ROADMAP.md**: Kubernetes migration plan

---

**Version**: 3.0 | **Updated**: 2026-03-12
**Changes**: Streamlined per Anthropic CLAUDE.md best practices - ruthlessly pruned
