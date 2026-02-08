# NixOS Infrastructure Consolidation & Sanitization Plan

**Target**: Make this NixOS infrastructure production-ready and publicly shareable  
**Branch**: feature/-secure → main  
**Status**: Complete | **Last Updated**: 2026-02-03

## 1.  Consolidation Strategy

### Summary
Standardize on `-declarative-container.nix` as the ONLY implementation. Migrate all hosts from binary to declarative container, delete redundant files, merge overlays, and update supporting services.

### Changes
| File | Action | Reason |
|------|--------|--------|
| `.nix` | Delete | Redundant binary package implementation |
| `-container.nix` | Delete | Redundant container implementation |
| `-docker.nix` | Delete | Redundant Docker implementation |
| `-fix-overlay.nix` + `-workaround-overlay.nix` | Merge | Create single consolidated overlay |
| `-declarative-container.nix` | Keep & Update | Make it the primary implementation |
| `-storage.nix` | Keep | Storage service support |
| `-backups.nix` | Keep | Backup service support |
| `-nginx.nix` | Keep | Nginx reverse proxy support |
| `-common.nix` | Update | Make it work with declarative containers |

### Details

#### Merge Overlays into Single File
**File**: `modules/-overlay.nix` (new)
- Combine `-fix-overlay.nix` and `-workaround-overlay.nix`
- Fix hasown dependency issue with proper implementation
- Support both -gateway and -tools

#### Update -common.nix
**File**: `modules/-common.nix`
- Remove binary package references
- Add declarative container support
- Update configuration patterns
- Maintain compatibility with existing settings

#### Migrate Host Configurations
**Hosts to Update**: zephyr, nexus, forge, sentry
1. Replace `services..enable = true;` with `services..declarative.enable = true;`
2. Remove binary package configurations
3. Keep existing environment file references (`/run/agenix/-env`)
4. Verify health monitoring settings

## 2. Security Hardening

### Mining API Security
**File**: `modules/mining.nix`
- **Current**: Mining API binds to all interfaces (0.0.0.0)
- **Fix**: Change to localhost-only binding (127.0.0.1)
- **Nginx Reverse Proxy**: Add for secure external access if needed

### Service Binding Verification
**Check All Services**:
```bash
# Verify no services bind to 0.0.0.0
grep -r "0\.0\.0\.0" --include="*.nix" modules/ hosts/
```

### Firewall Audit
**File**: `modules/networking.nix`
- Review all `networking.firewall.allowedTCPPorts` and `allowedUDPPorts`
- Remove unnecessary exposed ports
- Ensure only SSH (22), VR streaming (9757-9760), and Nginx (80/443) are externally accessible

### Security Documentation
**File**: `docs/SECURITY_AUDIT_CURRENT.md` (update)
- Document security model for each service
- Include container isolation details
- Add mining API security section
- Verify systemd hardening settings

## 3. File Cleanup

### Test Projects
**Directory**: `test/test-projects/`
- **Action**: Move to separate examples repository or delete
- **Reason**: Test projects are not production code and should not be in main repo

### Unused Files
**Files to Delete**:
- `modules/*.backup` - Backup files
- `modules/*.bak` - Backup files
- Commented-out code in all modules
- Abandoned features (e.g., old mining configurations)

### Script Organization
**Directory**: `scripts/`
- Create subdirectories:
  - `scripts/setup/` - Initial setup scripts
  - `scripts/maintenance/` - Maintenance and cleanup scripts
  - `scripts/monitoring/` - Performance and status scripts
  - `scripts/testing/` - Testing and validation scripts
- Update justfile to reference new paths

## 4. Secret Sanitization for Public Repo

### Identify Sensitive Files
**Current Sensitive Files** (in `secrets/` directory):
- `anthropic-api-key.age`
- `claude-api-key.age`
- `cachix-token.age`
- `garnix-netrc.age`
- `hf-token.age`
- `mining-api-token.age`
- `mining-wallet.age`
- `minio-cache-credentials.template`
- `openai-api-key.age`
- `-env.age`
- `-gateway-token.age`

### Gitignore Patterns
**File**: `.gitignore` (update)
```gitignore
# Secrets
secrets/*.age
!secrets/minio-cache-credentials.template
!secrets/age-secrets.nix

# Unencrypted secrets
secrets/*.key
secrets/*.txt
```

### Placeholder Files
**File**: `secrets/minio-cache-credentials.template` (existing)
- Create similar templates for all secrets
- Document required format in each template

### Secret Setup Documentation
**File**: `docs/SETUP.md` (new)
- Instructions for setting up Agenix
- List of required secrets
- Template file locations
- Command examples: `agenix -e <secret>.age`

### Git History Sanitization
```bash
# Verify no secrets in git history
git log --stat | grep -i "secret\|api\|key\|token"

# Clean git history if needed (use BFG Repo-Cleaner)
bfg --delete-files "*.age" --no-blob-protection
```

## 5. Documentation Overhaul

### Existing Documentation
**Files to Update**:
- `AGENTS.md` - Update with accurate statistics and structure
- `docs/README.md` - Make professional and GitHub-ready
- `docs/DEPLOYMENT_INSTRUCTIONS.md` - Update for new architecture

### New Documentation Files
**File**: `docs/ARCHITECTURE.md` (new)
- System architecture diagram
- Cluster topology
- Service relationships
- Design decisions and trade-offs

**File**: `docs/CONTRIBUTING.md` (new)
- Development guidelines
- Code standards (alejandra, statix)
- Branching strategy
- Pull request process

**File**: `docs/SETUP.md` (new)
- Step-by-step setup guide
- Prerequisites
- Agenix setup
- Cluster deployment
- Post-deployment verification

**File**: `LICENSE` (new)
- Choose appropriate license (MIT or Apache 2.0)

### Portfolio Presentation
**File**: `docs/PORTFOLIO.md` (new)
- Highlight technical achievements
- Security hardening showcase
- Infrastructure-as-code best practices
- Architecture diagrams
- Badges (NixOS version, license, build status)

## 6. Migration Steps (Ordered)

### Phase 1: Pre-Migration Preparation
1. **Create backup branch**: `git checkout -b feature/consolidation`
2. **Verify current state**: Run `just cluster-status` and `just cluster-build`
3. **Document existing configuration**: Take screenshots or notes of current service status

### Phase 2:  Consolidation
1. **Merge overlays**: Create `-overlay.nix` from existing overlays
2. **Update -common.nix**: Add declarative container support
3. **Update zephyr configuration**: Test migration on master node first
4. **Deploy zephyr**: `just deploy zephyr` and verify  functionality
5. **Repeat for other hosts**: nexus → forge → sentry

### Phase 3: Security Hardening
1. **Fix mining API binding**: Update `modules/mining.nix`
2. **Audit firewall rules**: Review `modules/networking.nix`
3. **Deploy changes**: `just cluster-deploy`
4. **Verify bindings**: `ss -tuln` on each host to check service bindings

### Phase 4: File Cleanup
1. **Move test projects**: Create separate repo or delete
2. **Delete unused files**: Remove backup files and commented code
3. **Organize scripts**: Create subdirectories in `scripts/`
4. **Update justfile**: Reference new script locations

### Phase 5: Secret Sanitization
1. **Create templates**: Add templates for all secrets
2. **Update .gitignore**: Add secret patterns
3. **Verify no secrets**: Run `git log --stat` and `grep -r "sk-\\|API_KEY\\|token"`
4. **Test Agenix setup**: Create test secrets and verify deployment

### Phase 6: Documentation Overhaul
1. **Update existing docs**: AGENTS.md, README.md, DEPLOYMENT_INSTRUCTIONS.md
2. **Create new docs**: ARCHITECTURE.md, CONTRIBUTING.md, SETUP.md, LICENSE
3. **Add portfolio content**: PORTFOLIO.md with achievements and diagrams

### Phase 7: Testing & Verification
1. **Full cluster deployment**: `just cluster-deploy`
2. **Test **: Verify on all hosts
3. **Test mining**: `just mining-status`
4. **Test gaming/VR**: Check WiVRn and SteamVR functionality
5. **Test distributed builds**: `nix build --builders-use-substitutes nixpkgs#hello`
6. **Final verification**: Run through entire checklist

## 7. Verification Checklist

- [ ] All 4 hosts (zephyr, nexus, forge, sentry) deploy successfully
- [ ]  declarative container runs on all hosts
- [ ]  health monitoring works
- [ ] Mining services run correctly with localhost-only API
- [ ] Gaming/VR functionality (WiVRn, SteamVR) intact
- [ ] Distributed builds work (or documented as disabled)
- [ ] No secrets in git history
- [ ] Documentation matches actual implementation
- [ ] README.md is professional and clear
- [ ] All tests pass
- [ ] Firewall rules are properly configured
- [ ] Services bind to localhost only unless explicitly needed externally

## 8. Rollback Plan

### If Migration Fails
1. **Revert changes**: `git reset --hard feature/-secure`
2. **Deploy previous version**: `just cluster-deploy`
3. **Restart services**: `systemctl restart  -storage` on all hosts
4. **Verify functionality**: Run through checklist again

### Backup Strategy
- Create system snapshots before migration
- Backup `/etc/nixos` directory
- Keep old generation: `nixos-rebuild switch --rollback` if needed

## 9. Post-Migration Steps

### Public Repository Preparation
1. **Create new repository**: On GitHub/GitLab
2. **Configure remote**: Update git remote
3. **Push initial commit**: With sanitized code
4. **Enable CI**: Garnix or GitHub Actions
5. **Add branch protection**: Require CI checks and reviews

### Production Monitoring
1. **Set up Prometheus/Grafana**: For system monitoring
2. **Configure alerting**: Email/SMS alerts for critical services
3. **Add logging**: Centralized logging with Loki/ELK

### Maintenance Plan
1. **Weekly updates**: `just cluster-update`
2. **Monthly security audits**: Review firewall rules and service bindings
3. **Quarterly backups**: Verify off-site backup functionality

---

## Quick Reference

### Key Files
| File | Purpose |
|------|---------|
| `modules/-declarative-container.nix` | Primary  implementation |
| `modules/-overlay.nix` | Consolidated hasown dependency fix |
| `modules/-common.nix` | Shared  configuration |
| `modules/mining.nix` | Mining service with localhost API |
| `modules/networking.nix` | Firewall and networking rules |
| `docs/SETUP.md` | Setup and secret management |

### Key Commands
```bash
# Deploy to all hosts
just cluster-deploy

# Verify  status
systemctl status -container-declarative

# Check service bindings
ss -tuln

# Verify mining API
curl -s http://127.0.0.1:34000/status

# Check git for secrets
grep -r "sk-\\|API_KEY\\|token" --exclude="*.age" .