# Anti-Patterns and Best Practice Deviations

## Critical Anti-Patterns Identified

### 1. Security Hardening Issues

#### SSH Configuration Anti-Patterns
- **`PermitRootLogin yes`** in `modules/ssh.nix` - Major security risk
- **`PasswordAuthentication yes`** for j_kro and root users
- **Passwordless sudo** for wheel group without justification
- **Multiple SSH keys** including root keys embedded in configuration

#### Mining Security Issues
- **Hardcoded wallet addresses** in multiple locations
- **Mining API ports** exposed without proper firewall restrictions
- **Steam-run wrapper** bypasses security controls for mining binaries

### 2. Code Duplication and Maintainability

#### Package Definition Duplication
- **Mining packages** defined in multiple places (overlay + host configs)
- **NVIDIA driver references** scattered across modules
- **Kernel parameter duplication** between configuration.nix and gaming.nix

#### Service Configuration Redundancy
- **Systemd slice definitions** duplicated in configuration.nix and systemd-slices.nix
- **Environment variables** spread across multiple modules
- **NVIDIA settings** repeated in gaming module and main config

### 3. Architectural Violations

#### Single Responsibility Principle Violations
- **`configuration.nix`** (510 lines) mixes kernel, hardware, services, users
- **`gaming.nix`** includes both VR setup AND performance tuning
- **Mining services** mix wrapper scripts, health monitoring, and service definitions

#### Dependency Inversion Violations
- **Hardcoded paths** to NVIDIA binaries throughout modules
- **Direct package references** instead of using overlay system consistently
- **Host-specific logic** leaking into shared modules

### 4. NixOS Best Practice Deviations

#### Module Organization Issues
- **Mixed concerns** in single modules (gaming + NVIDIA + WiVRn)
- **Missing mkIf guards** in some configuration sections
- **Inconsistent option naming** patterns across modules

#### Package Management Issues
- **steam-run dependency** used as workaround instead of proper packaging
- **Overlay fragmentation** - multiple mini-overlays instead of unified approach
- **Hardcoded versions** in custom package definitions

## Specific Problematic Patterns

### 1. The "Everything in configuration.nix" Anti-Pattern
```nix
# BAD: 510 lines mixing everything
boot.kernelParams = [ ... ];
hardware.nvidia = { ... };
security.sudo.extraRules = [ ... ];
services.xserver = { ... };
systemd.services = { ... };
```

### 2. The "Workaround with steam-run" Anti-Pattern
```nix
# PROBLEMATIC: Using steam-run as crutch
ExecStart = "${pkgs.steam-run}/bin/steam-run ${lolminerWrapper}/bin/lolminer-wrapper ..."
```

### 3. The "Hardcoded Values" Anti-Pattern
```nix
# PROBLEMATIC: Hardcoded wallet addresses
wallet = "WALLET_PREFIX.NODE_NAME";
pool = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
```

### 4. The "Duplicate Slice Definitions" Anti-Pattern
```nix
# DUPLICATED: In both configuration.nix and systemd-slices.nix
systemd.slices."gaming.slice" = { ... };
```

## Recommendations for Remediation

### 1. Security Hardening Priority 1
```nix
# FIX: Disable root login and use key-only auth
services.openssh = {
  enable = true;
  settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = "no";
  };
};
```

### 2. Modularization Priority 2
```nix
# SPLIT: Break down large modules
modules/
├── kernel/          # Kernel parameters and optimization
├── hardware/        # NVIDIA, GPU, device drivers
├── security/        # SSH, sudo, user permissions
└── services/        # Individual service modules
```

### 3. Configuration Consolidation Priority 3
```nix
# CONSOLIDATE: Single source of truth for repeated configs
modules/lib/
├── nvidia-options.nix
├── mining-config.nix
└── gaming-config.nix
```

### 4. Secret Management Priority 4
```nix
# IMPLEMENT: Use agenix for sensitive data
{
  age.secrets.mining-wallet.file = ./secrets/mining-wallet.age;
  services.mining.walletFile = config.age.secrets.mining-wallet.path;
}
```

## Best Practice Violations Summary

| Category | Violation | Severity | Impact |
|----------|-----------|----------|---------|
| **Security** | PermitRootLogin yes | CRITICAL | Remote root access |
| **Security** | PasswordAuthentication yes | HIGH | Brute force vulnerability |
| **Architecture** | 510-line configuration.nix | MEDIUM | Maintainability issues |
| **Code Quality** | Duplicate slice definitions | MEDIUM | Conflicting configurations |
| **Packaging** | steam-run workarounds | LOW | Performance overhead |
| **Data Handling** | Hardcoded secrets | MEDIUM | Security/privacy risk |

## Immediate Action Items

1. **Disable SSH root login** and password authentication
2. **Move hardcoded wallets/secrets** to agenix encrypted files
3. **Split configuration.nix** into focused modules
4. **Consolidate duplicate systemd slice definitions**
5. **Create unified overlay** instead of fragmented approach
6. **Add mkIf guards** to all conditional configurations

This analysis reveals that while the codebase demonstrates advanced NixOS capabilities, it contains several security and architectural anti-patterns that should be addressed for production readiness.