# Documentation Index & Navigation

## Master Documentation Map

This index provides navigation across the extensive documentation set for the Reverb-OS NixOS cluster project. Due to previous documentation sprawl, information exists across multiple files that will be gradually consolidated.

## Current Documentation Structure

### Primary Entry Points
- **[README.md](./README.md)** - Project overview, quick start, architecture
- **[AGENTS.md](./AGENTS.md)** - Master technical documentation (current version)
- **[CLAUDE.md](./CLAUDE.md)** - *(Symlink to AGENTS.md)* - Claude access point
- **[QWEN.md](./QWEN.md)** - *(Symlink to AGENTS.md)* - Qwen access point
- **[DOCUMENTATION_STRATEGY.md](./DOCUMENTATION_STRATEGY.md)** - This document (refactoring plan)

### System Configuration
- **[configuration.nix](./configuration.nix)** - Shared cluster configuration
- **[hosts/](./hosts/)** - Per-node configurations (zephyr, nexus, forge, sentry)
- **[modules/](./modules/)** - Modular system configurations
- **[secrets/](./secrets/)** - Agenix encrypted secrets

### Build & Deployment
- **[flake.nix](./flake.nix)** - Nix flake configuration
- **[justfile](./justfile)** - Automation commands
- **[colmena.nix](./colmena.nix)** - Cluster deployment
- **[garnix.yaml](./garnix.yaml)** - CI/CD configuration

### Cluster Operations
- **[Tailscale Setup](./docs/TAILSCALE_SETUP.md)** - VPN configuration guide
- **[Mining Operations](./docs/MINING_CLUSTER_STATUS.md)** - Mining configuration
- **[Gaming Configuration](./docs/KDE_PLASMA_FIX_GUIDE.md)** - VR/gaming setup
- **[OpenClaw](./OPENCLAW-SUMMARY.md)** - AI orchestration system

### Security & Auditing
- **[Security Audit Report](./docs/SECURITY_AUDIT_REPORT.md)** - Comprehensive security assessment
- **[Quick Security Fixes](./docs/QUICK_FIXES.md)** - Immediate security improvements
- **[OpenClaw Security](./docs/OPENCLAW-TAILSCALE-SECURITY.md)** - AI security measures
- **[Security Current](./docs/SECURITY_AUDIT_CURRENT.md)** - Current security status

### Development & Troubleshooting
- **[Sprawl Cleanup Implementation](./docs/SPRAWL_CLEANUP_IMPLEMENTATION.md)** - Code refactoring guide
- **[Sprawl Cleanup Progress](./docs/SPRAWL_CLEANUP_PROGRESS.md)** - Refactoring progress
- **[Boot Error Analysis](./docs/BOOT_ERROR_ANALYSIS.md)** - System boot troubleshooting
- **[Improvement Plan](./docs/IMPROVEMENT_PLAN.md)** - Enhancement roadmap

### Architecture & Design
- **[Architecture Overview](./docs/ARCHITECTURE.md)** - System design documentation
- **[Reverb-OS Architecture](./docs/REVERB-OS-ARCHITECTURE.md)** - Project-specific architecture
- **[Modernization Plan](./docs/MODERNIZATION-PLAN.md)** - Technology roadmap
- **[Portfolio Documentation](./docs/PORTFOLIO.md)** - Technical achievements showcase

### Contributing & Development
- **[Contributing Guidelines](./docs/CONTRIBUTING.md)** - Development practices
- **[Quick Start](./docs/QUICK_START.md)** - Rapid deployment guide
- **[Setup Guide](./docs/SETUP.md)** - Installation instructions
- **[Script Organization](./docs/SCRIPT_ORGANIZATION.md)** - Code organization

## Documentation Status

### 🔴 High Priority Consolidation
The following files contain overlapping information that needs consolidation:
- Multiple security audit documents (4 files)
- Multiple deployment guides (3 files) 
- Multiple quick start guides (4 files)
- Scattered OpenClaw documentation (5+ files)

### 🟡 Medium Priority Updates
- Architecture documentation consistency
- Module documentation standards
- API documentation for custom modules

### 🟢 Stable Documentation
- Core system configuration files
- Flake and deployment infrastructure
- Main project overview (README.md)

## Search Tips

Due to the distributed nature of documentation, when searching for information:

1. **Start with AGENTS.md** - Contains most comprehensive current system documentation
2. **Check the docs/ directory** - Historical and specialized documentation
3. **Review module-specific files** - For implementation details
4. **Use grep for specific terms** - Across all documentation files

Example search:
```bash
grep -r "tailscale" /etc/nixos/ --include="*.md"
grep -r "openclaw" /etc/nixos/ --include="*.md" 
grep -r "mining" /etc/nixos/ --include="*.md"
```

## Planned Consolidation Areas

Over the next sprint, the following consolidation efforts are planned:

### Q1 2026 Effort
- [ ] Merge security audit files into single SECURITY.md
- [ ] Combine deployment guides into unified DEPLOYMENT.md
- [ ] Consolidate OpenClaw documentation into OPENCLAW.md
- [ ] Create unified TROUBLESHOOTING.md from scattered guides

### Q2 2026 Effort
- [ ] Create comprehensive ARCHITECTURE.md from multiple sources
- [ ] Update README.md with condensed information from AGENTS.md
- [ ] Archive obsolete documentation files
- [ ] Implement documentation validation in CI/CD

## Navigation Aids

For AI Assistants (Claude, Qwen, etc.):
- Use **[AGENTS.md](./AGENTS.md)** for most comprehensive system information
- Use **[README.md](./README.md)** for project overview and context
- Reference specific module files for implementation details
- Check **[DOCUMENTATION_STRATEGY.md](./DOCUMENTATION_STRATEGY.md)** for structure

For Developers:
- Use **[justfile](./justfile)** commands for system operations
- Refer to **[flake.nix](./flake.nix)** for system dependencies
- Check **[modules/](./modules/)** directory for reusable components
- Use **[secrets/](./secrets/)** for sensitive configuration

## Maintenance Guidelines

When updating documentation:
1. Update the primary source file listed above
2. Ensure cross-references remain accurate
3. Add new information to appropriate category
4. Update this index when new documentation is created
5. Mark obsolete documentation for future cleanup

---

*Index Version: 1.0*  
*Last Updated: 2026-02-03*  
*Total Documentation Files Indexed: 53+*  
*Status: Active Navigation Aid*