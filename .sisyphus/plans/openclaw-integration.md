# OpenClaw Integration Work Plan

## Context

### Original Request
Integrate OpenClaw.ai personal AI assistant into the existing NixOS cluster (4 hosts: zephyr, nexus, forge, sentry) using the nix-openclaw flake.

### Interview Summary
**Key Discussions**:
- User wants to implement OpenClaw across their NixOS cluster
- OpenClaw is a personal AI assistant accessible via Telegram/Discord that performs actions on local machines
- Uses nix-openclaw flake (github:openclaw/nix-openclaw) for declarative NixOS integration
- Current cluster: 4 hosts (zephyr, nexus, forge, sentry) with 51-core distributed build pool
- Uses Home Manager, Agenix for secrets, modular configuration in /data/@projects/infra/nixos/
- GPU: NVIDIA RTX 3090 with beta driver on zephyr
- Desktop: KDE Plasma 6 + Wayland

**Research Findings**:
- nix-openclaw provides comprehensive Home Manager module
- Supports systemd user services on Linux, launchd on macOS
- Plugin ecosystem with first-party tools from nix-steipete-tools
- Requires Node.js 22, pnpm 10, vips for image processing
- Compatible with existing NixOS practices (Agenix, Home Manager, flakes)
- Architecture: Telegram/Discord → Gateway → Tools → Local machine actions
- Supports multiple instances per user (prod/test)
- Built-in plugins: summarize, peekaboo, oracle, poltergeist, sag, camsnap, gogcli, bird, sonoscli, imsg

### Metis Review
**Identified Gaps** (addressed):
- [x] Need to clarify which hosts get OpenClaw → All 4 hosts, different configs
- [x] Secret management via Agenix → Use existing Agenix setup
- [x] Per-host configuration differences → zephyr full, servers headless
- [x] Testing strategy → Start with zephyr, then deploy to others
- [x] Rollback procedures → Document home-manager rollback commands

---

## Work Objectives

### Core Objective
Deploy OpenClaw.ai personal AI assistant across the NixOS cluster with user-level Home Manager integration, using Agenix for secrets management, and per-host configurations optimized for workstation vs. server use cases.

### Concrete Deliverables
- Modified `flake.nix` with nix-openclaw input
- New module `modules/openclaw.nix` for cluster-wide configuration
- User documents directory with AGENTS.md, SOUL.md, TOOLS.md
- Agenix secrets configuration for Telegram bot token and Anthropic API key
- Per-host configuration files (zephyr full, servers headless)
- Verification and rollback procedures

### Definition of Done
- [ ] OpenClaw gateway service runs on all 4 hosts
- [ ] Telegram bot responds to messages from authorized users
- [ ] Built-in plugins (summarize, peekaboo, oracle) work on zephyr
- [ ] Headless configuration works on nexus, forge, sentry
- [ ] Secrets properly managed via Agenix
- [ ] Rollback procedures tested and documented

### Must Have
- Home Manager integration for user `j_kro`
- Agenix-based secret management
- systemd user service on all hosts
- Basic plugins enabled (summarize, peekaboo)
- Per-host configuration differentiation

### Must NOT Have (Guardrails)
- System-wide service (runs as user only)
- macOS-specific plugins on Linux servers (poltergeist, imsg)
- GUI tools on headless servers
- Hardcoded secrets in configuration files
- Production API keys in plaintext

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES (Home Manager, Agenix)
- **User wants tests**: Manual verification only
- **Framework**: N/A (NixOS configuration, not code)

### Manual Execution Verification

**For Each Host:**
- [ ] Using interactive_bash (tmux session):
  - Command: `systemctl --user status openclaw-gateway`
  - Expected: Service active (running)
  - Exit code: 0

- [ ] Using interactive_bash (tmux session):
  - Command: `journalctl --user -u openclaw-gateway -n 50`
  - Expected: No errors, "Gateway started successfully" message
  - Exit code: 0

- [ ] Telegram verification:
  - Send message to bot: "Hello"
  - Expected: Bot responds with greeting and bootstrap ritual
  - Evidence: Screenshot of Telegram conversation

**For zephyr (full features):**
- [ ] Plugin verification:
  - Command: `ls ~/.openclaw/workspace/skills/`
  - Expected: summarize, peekaboo, oracle directories present
  
- [ ] Screenshot capability:
  - Telegram message: "What's on my screen?"
  - Expected: Bot takes screenshot and describes it
  - Evidence: Screenshot received in Telegram

**For servers (headless):**
- [ ] Verify no GUI plugins:
  - Command: `ls ~/.openclaw/workspace/skills/ | grep -E "peekaboo|poltergeist"`
  - Expected: Empty output (no GUI plugins)

**Evidence Required:**
- [ ] Service status output captured
- [ ] Telegram conversation screenshots
- [ ] Journal logs showing successful startup

---

## Task Flow

```
Task 1 (flake.nix) → Task 2 (openclaw.nix module) → Task 3 (documents)
       ↓
Task 4 (secrets) → Task 5 (zephyr test) → Task 6 (server configs)
       ↓
Task 7 (cluster deploy) → Task 8 (verification & rollback docs)
```

## Parallelization

| Group | Tasks | Reason |
|-------|-------|--------|
| A | 1, 2, 3 | Independent file creation |
| B | 4 | Depends on nothing, but must be done before testing |

| Task | Depends On | Reason |
|------|------------|--------|
| 5 | 1, 2, 3, 4 | Needs all config in place before testing |
| 6 | 2 | Uses module patterns from Task 2 |
| 7 | 5, 6 | Needs zephyr working and server configs ready |
| 8 | 7 | Documents final state |

---

## TODOs

- [ ] 1. Add nix-openclaw input to flake.nix

  **What to do**:
  - Add `nix-openclaw.url = "github:openclaw/nix-openclaw";` to inputs
  - Add `nix-openclaw.inputs.nixpkgs.follows = "nixpkgs";` to follow existing nixpkgs
  - Add `nix-openclaw.inputs.home-manager.follows = "home-manager";` to follow existing home-manager
  - Pass `inputs.nix-openclaw` to specialArgs in mkNixosSystem

  **Must NOT do**:
  - Do not pin to specific revision initially (use latest)
  - Do not add to commonModules directly (Home Manager integration only)

  **Parallelizable**: YES (with 2, 3)

  **References**:
  - `flake.nix:1-50` - Current inputs structure
  - `flake.nix:127-142` - mkNixosSystem function
  - nix-openclaw docs: Home Manager module integration pattern

  **Acceptance Criteria**:
  - [ ] `nix flake check` passes without errors
  - [ ] `nix flake metadata` shows nix-openclaw in inputs
  - [ ] Input follows nixpkgs and home-manager as specified

  **Manual Verification**:
  - [ ] Command: `nix flake check .#zephyr`
  - [ ] Expected: Build succeeds
  - [ ] Exit code: 0

  **Commit**: YES
  - Message: `feat(flake): add nix-openclaw input for AI assistant`
  - Files: `flake.nix`

---

- [ ] 2. Create OpenClaw module (modules/openclaw.nix)

  **What to do**:
  - Create new module file with Home Manager integration
  - Import nix-openclaw.homeManagerModules.openclaw
  - Configure base OpenClaw settings with documents directory
  - Set up providers (Telegram, Anthropic) with Agenix secret paths
  - Enable first-party plugins (summarize, peekaboo, oracle)
  - Configure systemd user service settings
  - Add options for per-host customization

  **Must NOT do**:
  - Do not hardcode secrets (use Agenix paths)
  - Do not enable macOS-only plugins on Linux
  - Do not create system-wide service (user-level only)

  **Parallelizable**: YES (with 1, 3)

  **References**:
  - `modules/default.nix:1-15` - Module import pattern
  - `home.nix:1-50` - Home Manager user configuration pattern
  - nix-openclaw: `nix/modules/home-manager/openclaw.nix` - Full module options
  - nix-openclaw docs: Configuration examples for providers and plugins

  **Acceptance Criteria**:
  - [ ] Module file created at `modules/openclaw.nix`
  - [ ] Module imports nix-openclaw Home Manager module
  - [ ] Telegram provider configured with Agenix secret path
  - [ ] Anthropic provider configured with Agenix secret path
  - [ ] First-party plugins enabled (summarize, peekaboo, oracle)
  - [ ] Documents directory option exposed
  - [ ] Module added to `modules/default.nix` imports

  **Manual Verification**:
  - [ ] Command: `nix flake check .#zephyr`
  - [ ] Expected: No evaluation errors
  - [ ] Command: `nix eval .#nixosConfigurations.zephyr.config.home-manager.users.j_kro.programs.openclaw.enable`
  - [ ] Expected: Returns `true`

  **Commit**: YES
  - Message: `feat(modules): add OpenClaw AI assistant module`
  - Files: `modules/openclaw.nix`, `modules/default.nix`

---

- [ ] 3. Create user documents directory with required files

  **What to do**:
  - Create directory `home/openclaw-docs/`
  - Create `AGENTS.md` - Define AI personality, behavior, and capabilities
  - Create `SOUL.md` - Core principles, decision-making guidelines
  - Create `TOOLS.md` - Documentation of available tools and how to use them
  - Files should be generic templates that user can customize

  **Must NOT do**:
  - Do not include real secrets or API keys
  - Do not include personal information
  - Do not make files executable

  **Parallelizable**: YES (with 1, 2)

  **References**:
  - nix-openclaw docs: "Configuration" section for documents structure
  - nix-openclaw templates: `templates/agent-first/documents/`

  **Acceptance Criteria**:
  - [ ] Directory created at `home/openclaw-docs/`
  - [ ] `AGENTS.md` created with AI personality template
  - [ ] `SOUL.md` created with core principles template
  - [ ] `TOOLS.md` created with tools documentation template
  - [ ] All files are valid markdown
  - [ ] No secrets or personal information in templates

  **Manual Verification**:
  - [ ] Command: `ls -la home/openclaw-docs/`
  - [ ] Expected: Shows AGENTS.md, SOUL.md, TOOLS.md
  - [ ] Command: `head -20 home/openclaw-docs/AGENTS.md`
  - [ ] Expected: Shows valid markdown content

  **Commit**: YES
  - Message: `docs(openclaw): add user documents templates`
  - Files: `home/openclaw-docs/AGENTS.md`, `home/openclaw-docs/SOUL.md`, `home/openclaw-docs/TOOLS.md`

---

- [ ] 4. Configure Agenix secrets for OpenClaw

  **What to do**:
  - Create secret files for Telegram bot token
  - Create secret files for Anthropic API key
  - Update `secrets/agenix-secrets.nix` with new secret definitions
  - Set appropriate permissions (0600)
  - Document secret creation process for user

  **Must NOT do**:
  - Do not commit plaintext secrets
  - Do not use weak permissions on secret files
  - Do not hardcode secret values in configuration

  **Parallelizable**: NO (must be done before testing, but independent of other tasks)

  **References**:
  - `configuration.nix:56-61` - Agenix module import
  - `secrets/agenix-secrets.nix` - Existing secret definitions pattern
  - Agenix docs: Secret creation and management

  **Acceptance Criteria**:
  - [ ] Secret files created (not committed, just documented)
  - [ ] `secrets/agenix-secrets.nix` updated with Telegram bot token secret
  - [ ] `secrets/agenix-secrets.nix` updated with Anthropic API key secret
  - [ ] Permissions set to 0600 for both secrets
  - [ ] Paths documented: `/run/agenix/openclaw-telegram-token`, `/run/agenix/openclaw-anthropic-key`

  **Manual Verification**:
  - [ ] Command: `sudo agenix -e secrets/openclaw-telegram-token.age`
  - [ ] Expected: Editor opens for secret creation
  - [ ] After creation: `ls -la /run/agenix/openclaw-*`
  - [ ] Expected: Files exist with correct permissions

  **Commit**: YES (configuration only, not secrets)
  - Message: `feat(secrets): add Agenix configuration for OpenClaw`
  - Files: `secrets/agenix-secrets.nix`
  - Note: Secret files themselves are NOT committed (encrypted with agenix)

---

- [ ] 5. Test OpenClaw deployment on zephyr (main workstation)

  **What to do**:
  - Deploy configuration to zephyr with full features
  - Enable all first-party plugins (summarize, peekaboo, oracle)
  - Configure for GUI environment (screenshots, etc.)
  - Verify systemd user service starts
  - Test Telegram bot communication
  - Verify plugins are loaded

  **Must NOT do**:
  - Do not deploy to other hosts until zephyr is verified
  - Do not skip verification steps
  - Do not ignore service startup errors

  **Parallelizable**: NO (depends on 1, 2, 3, 4)

  **References**:
  - `hosts/zephyr/configuration.nix` - Host-specific configuration
  - nix-openclaw docs: Verification commands
  - `justfile` - Deployment commands

  **Acceptance Criteria**:
  - [ ] Configuration builds successfully: `nixos-rebuild switch --flake .#zephyr`
  - [ ] systemd user service active: `systemctl --user status openclaw-gateway`
  - [ ] No errors in logs: `journalctl --user -u openclaw-gateway`
  - [ ] Telegram bot responds to messages
  - [ ] Plugins loaded: `ls ~/.openclaw/workspace/skills/`
  - [ ] Screenshot capability works (zephyr only)

  **Manual Verification**:
  - [ ] Command: `just switch` or `sudo nixos-rebuild switch --flake .#zephyr`
  - [ ] Expected: Build succeeds, system switches
  - [ ] Command: `systemctl --user status openclaw-gateway`
  - [ ] Expected: Shows "active (running)"
  - [ ] Telegram: Send "Hello" to bot
  - [ ] Expected: Bot responds with greeting
  - [ ] Telegram: Send "What's on my screen?"
  - [ ] Expected: Bot takes and sends screenshot
  - [ ] Evidence: Screenshots saved to `.sisyphus/evidence/openclaw-zephyr-*.png`

  **Commit**: YES
  - Message: `feat(hosts/zephyr): enable OpenClaw with full features`
  - Files: `hosts/zephyr/configuration.nix`

---

- [ ] 6. Configure per-host settings for servers (nexus, forge, sentry)

  **What to do**:
  - Create headless configuration for each server
  - Disable GUI plugins (peekaboo, poltergeist, camsnap)
  - Enable only server-appropriate plugins (summarize, oracle)
  - Configure for automation/monitoring use cases
  - Test each configuration builds

  **Must NOT do**:
  - Do not enable GUI plugins on headless servers
  - Do not configure macOS-specific features
  - Do not skip testing each host

  **Parallelizable**: YES (after Task 2, can work on all 3 servers in parallel)

  **References**:
  - `hosts/nexus/configuration.nix` - Server configuration pattern
  - `hosts/forge/configuration.nix` - Server configuration pattern
  - `hosts/sentry/configuration.nix` - Server configuration pattern
  - Task 2 output: `modules/openclaw.nix` module options

  **Acceptance Criteria**:
  - [ ] nexus configuration updated with headless OpenClaw
  - [ ] forge configuration updated with headless OpenClaw
  - [ ] sentry configuration updated with headless OpenClaw
  - [ ] All configurations build: `nix flake check`
  - [ ] GUI plugins disabled on all servers
  - [ ] Server-appropriate plugins enabled

  **Manual Verification**:
  - [ ] Command: `nix flake check .#nexus .#forge .#sentry`
  - [ ] Expected: All builds succeed
  - [ ] Command: `nix eval .#nixosConfigurations.nexus.config.home-manager.users.j_kro.programs.openclaw.firstParty.peekaboo.enable`
  - [ ] Expected: Returns `false` (disabled on servers)

  **Commit**: YES
  - Message: `feat(hosts): add OpenClaw headless configuration to servers`
  - Files: `hosts/nexus/configuration.nix`, `hosts/forge/configuration.nix`, `hosts/sentry/configuration.nix`

---

- [ ] 7. Deploy OpenClaw to remaining cluster hosts

  **What to do**:
  - Deploy to nexus, forge, sentry using colmena or nixos-rebuild
  - Verify each deployment succeeds
  - Check service status on each host
  - Test Telegram bot on each host
  - Document any host-specific issues

  **Must NOT do**:
  - Do not deploy all at once without verification
  - Do not ignore deployment errors
  - Do not skip post-deployment verification

  **Parallelizable**: NO (sequential deployment recommended for safety)

  **References**:
  - `justfile` - `just cluster-deploy` command
  - Colmena documentation for multi-host deployment
  - Task 5 verification procedures

  **Acceptance Criteria**:
  - [ ] Successfully deployed to nexus
  - [ ] Successfully deployed to forge
  - [ ] Successfully deployed to sentry
  - [ ] All services running on all hosts
  - [ ] Telegram bot responds from all hosts
  - [ ] No critical errors in logs

  **Manual Verification**:
  - [ ] Command: `just cluster-deploy`
  - [ ] Expected: Deploys to all hosts successfully
  - [ ] On each host: `systemctl --user status openclaw-gateway`
  - [ ] Expected: All show "active (running)"
  - [ ] Telegram: Send "Hello" from each host
  - [ ] Expected: Bot responds from each host
  - [ ] Evidence: Service status outputs captured

  **Commit**: NO (deployment is runtime operation, not configuration change)

---

- [ ] 8. Create verification and rollback procedures documentation

  **What to do**:
  - Document verification commands for each host
  - Create rollback procedures using home-manager generations
  - Document troubleshooting steps
  - Add quick reference guide for common operations
  - Update AGENTS.md with cluster-specific capabilities

  **Must NOT do**:
  - Do not skip documenting rollback procedures
  - Do not make procedures host-specific without reason
  - Do not omit common failure modes

  **Parallelizable**: NO (depends on Task 7 completion)

  **References**:
  - nix-openclaw docs: Troubleshooting section
  - Home Manager manual: Generations and rollback
  - Task 5-7 verification procedures

  **Acceptance Criteria**:
  - [ ] Verification commands documented for all hosts
  - [ ] Rollback procedures documented (home-manager switch --rollback)
  - [ ] Troubleshooting guide created
  - [ ] Quick reference added to AGENTS.md
  - [ ] Documentation committed to repository

  **Manual Verification**:
  - [ ] Command: `cat home/openclaw-docs/OPERATIONS.md`
  - [ ] Expected: Shows verification and rollback procedures
  - [ ] Test rollback: `home-manager switch --rollback`
  - [ ] Expected: Rolls back to previous generation
  - [ ] Test verify: `systemctl --user status openclaw-gateway`
  - [ ] Expected: Shows service status

  **Commit**: YES
  - Message: `docs(openclaw): add verification and rollback procedures`
  - Files: `home/openclaw-docs/OPERATIONS.md`, `home/openclaw-docs/AGENTS.md`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `feat(flake): add nix-openclaw input for AI assistant` | flake.nix | `nix flake check` |
| 2 | `feat(modules): add OpenClaw AI assistant module` | modules/openclaw.nix, modules/default.nix | `nix eval .#nixosConfigurations.zephyr.config.home-manager.users.j_kro.programs.openclaw.enable` |
| 3 | `docs(openclaw): add user documents templates` | home/openclaw-docs/* | `ls home/openclaw-docs/` |
| 4 | `feat(secrets): add Agenix configuration for OpenClaw` | secrets/agenix-secrets.nix | `nix flake check` |
| 5 | `feat(hosts/zephyr): enable OpenClaw with full features` | hosts/zephyr/configuration.nix | Deploy and test on zephyr |
| 6 | `feat(hosts): add OpenClaw headless configuration to servers` | hosts/nexus/configuration.nix, hosts/forge/configuration.nix, hosts/sentry/configuration.nix | `nix flake check .#nexus .#forge .#sentry` |
| 8 | `docs(openclaw): add verification and rollback procedures` | home/openclaw-docs/OPERATIONS.md, home/openclaw-docs/AGENTS.md | Review documentation |

---

## Success Criteria

### Verification Commands
```bash
# Check all hosts have OpenClaw enabled
nix eval .#nixosConfigurations.zephyr.config.home-manager.users.j_kro.programs.openclaw.enable
nix eval .#nixosConfigurations.nexus.config.home-manager.users.j_kro.programs.openclaw.enable
nix eval .#nixosConfigurations.forge.config.home-manager.users.j_kro.programs.openclaw.enable
nix eval .#nixosConfigurations.sentry.config.home-manager.users.j_kro.programs.openclaw.enable
# Expected: all return "true"

# Verify service status on each host
ssh zephyr systemctl --user status openclaw-gateway
ssh nexus systemctl --user status openclaw-gateway
ssh forge systemctl --user status openclaw-gateway
ssh sentry systemctl --user status openclaw-gateway
# Expected: all show "active (running)"

# Check logs for errors
ssh zephyr journalctl --user -u openclaw-gateway -n 50
# Expected: No ERROR or FATAL messages
```

### Final Checklist
- [ ] All "Must Have" present (Home Manager, Agenix, systemd, plugins, per-host configs)
- [ ] All "Must NOT Have" absent (no system-wide service, no macOS plugins on Linux, no hardcoded secrets)
- [ ] All hosts deployed and verified
- [ ] Telegram bot responds on all hosts
- [ ] Rollback procedures tested
- [ ] Documentation complete
