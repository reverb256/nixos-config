# PROJECT KNOWLEDGE BASE

**Generated:** 2026-01-26
**Commit:** 88d3861
**Branch:** main
**Mode:** Update

## OVERVIEW
Comprehensive documentation and testing infrastructure for NixOS distributed build cluster with VR gaming and cryptocurrency mining capabilities.

## STRUCTURE
```
/etc/nixos/docs/
├── AGENTS.md                      # This file (documentation domain)
├── MODULE_REFACTOR_PLAN.md        # Code organization improvements
├── PERFORMANCE_OPTIMIZATION_PLAN.md # System performance enhancements
├── QUICK_FIXES.md                 # Immediate security fixes
├── README.md                      # Main project documentation
└── SECURITY_AUDIT.md              # Security analysis and fixes
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Documentation | docs/ | All project docs and guides |
| Quick fixes | docs/QUICK_FIXES.md | Security improvements |
| Performance | docs/PERFORMANCE_OPTIMIZATION_PLAN.md | System optimization |
| Security | docs/SECURITY_AUDIT.md | Security hardening |
| Module refactoring | docs/MODULE_REFACTOR_PLAN.md | Code organization |

| Testing | build-and-test.sh | Master test orchestrator |
| Shell tests | test-fish-syntax.fish | Fish functionality tests |
| Detection tests | test-detection.fish | Project detection tests |

## CONVENTIONS
- **Documentation format**: Markdown with clear section headers
- **Testing**: Multi-layer validation with VM isolation
- **Security**: agenix secrets for sensitive data
- **Performance**: Workload isolation via systemd slices
- **Cluster**: 51-core distributed build pool across 4 hosts
- **VR Gaming**: WiVRn + SteamVR with smart mining pause
- **Mining**: Auto-pause during VR/gaming sessions


## ANTI-PATTERNS
- **NEVER commit secrets** - Use agenix for sensitive configuration
- **NEVER hardcode API keys** - Store in agenix secrets
- **NEVER expose mining ports** - Restrict to localhost only
- **NEVER skip testing** - Always run build-and-test.sh before deployment
- **NEVER edit hardware-configuration.nix** - Auto-generated file
- **NEVER duplicate packages** - Use centralized system-packages.nix
- **NEVER add services to main config** - Use dedicated modules
- **NEVER ignore security fixes** - Address all vulnerabilities immediately