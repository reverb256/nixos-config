# NixOS Configuration Best Practices: Public/Private Separation

## 🎯 Goal
Maintain a public repository with reusable infrastructure patterns while keeping private network details secure.

## 🏗️ Core Principles

### 1. **Separation of Concerns**
- **Public Config**: Infrastructure patterns, module definitions, reusable components
- **Private Config**: Specific IP addresses, hostnames, credentials, deployment specifics
- **Public Repo**: Contains only reusable, anonymized patterns  
- **Local/Private**: Contains your specific deployment values

### 2. **Parameterization**
- Use NixOS options system for configuration points
- Provide dummy defaults for public repository
- Allow private overrides through import layering

## 📋 Implementation Strategy

### **Phase 1: Public Interface Definition**
Create public-facing modules that define the interface:

```nix
# public/modules/mining.nix
{ config, lib, pkgs, ... }: let
  cfg = config.services.cluster-mining;
in {
  options.services.cluster-mining = {
    enable = lib.mkEnableOption "Cluster mining services";
    
    # Public interface with optional private implementation
    walletAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;  # Null means disabled in public
      description = "Mining wallet address (null disables)";
    };
    
    nodes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.wallet = lib.mkOption {
          type = lib.types.str;
          description = "Per-node wallet override";
        };
      });
      default = {};
      description = "Node-specific mining configurations";
    };
  };
  
  config = lib.mkIf (cfg.walletAddress != null) {
    # Only configure if private value is provided
    services.xmrig = {
      enable = true;
      # Use the private wallet address
    };
  };
}
```

### **Phase 2: Private Implementation**
Provide private values separately:

```nix
# private/node-configs/zephyr.nix
{ config, lib, ... }: {
  services.cluster-mining = {
    walletAddress = "WALLET_PREFIX.NODE_NAME";
    nodes.zephyr.wallet = "WALLET_PREFIX.NODE_NAME";
  };
}
```

### **Phase 3: Integration**
Combine in main flake:

```nix
# flake.nix
{
  outputs = { ... }: {
    nixosConfigurations = {
      zephyr = { pkgs, ... }: {
        imports = [
          ./public/modules/mining.nix      # Public pattern
          ./private/node-configs/zephyr.nix # Private values
        ];
      };
    };
  };
}
```

## 🤖 Automation Tools

### **Validation Script**
Automatically check for private data in public areas:

```bash
#!/usr/bin/env bash
# scripts/validate-public.sh

check_for_private_data() {
    local found_issues=0
    
    # Check for private patterns in public directory
    if grep -r "10\.1\.1\." public/ --include="*.nix"; then
        echo "ERROR: Private IPs found in public/"
        found_issues=1
    fi
    
    if grep -r "krxXVNVMM7\." public/ --include="*.nix"; then
        echo "ERROR: Wallet IDs found in public/"
        found_issues=1
    fi
    
    return $found_issues
}

before_commit() {
    if check_for_private_data; then
        echo "❌ Commit blocked: private data detected"
        exit 1
    else
        echo "✅ Commit OK: no private data detected"
        exit 0
    fi
}

"$@"
```

### **Pre-commit Hook**
```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit
exec ./.git/hooks/validate-public.sh before_commit
```

## 🔄 Workflows

### **Development Workflow**
1. Modify public modules (patterns, reusable components)
2. Test with dummy values in public repo
3. Commit and push public changes
4. Update private configs locally (not committed)

### **Release Workflow** 
1. Tag public version for others to use
2. Keep private configs for your deployment
3. Document how others can adapt the patterns

## 🔐 Security Benefits

### **Defense in Depth**
1. **Configuration Layer**: No private values in Nix configs
2. **Commit Layer**: Pre-commit hooks prevent accidents  
3. **Repository Layer**: Separate public/private concerns
4. **Runtime Layer**: Values only resolved at build time

### **Risk Mitigation**
- **IP Exposure**: Prevented by parameterization
- **Credential Exposure**: Handled by agenix
- **Pattern Exposure**: Actually desired - shows infrastructure patterns

## 🎓 Best Practices Summary

| Practice | Benefit | Implementation |
|----------|---------|----------------|
| **Public Interface Patterns** | Reusable, shareable code | NixOS options with dummy defaults |
| **Private Value Injection** | Secure customization | Separate import files |
| **Automated Validation** | Prevent accidents | Pre-commit hooks |
| **Layered Configuration** | Clean separation | Public + Private imports |
| **Dummy Values** | Safe public examples | Null/placeholder defaults |

## 🚀 Quick Implementation

The `SETUP_PARAMETERIZED_REPO.sh` script will create this structure automatically, allowing you to maintain a public repository with reusable patterns while keeping your private deployment details secure.

This approach follows NixOS best practices and allows others to benefit from your infrastructure patterns while protecting your private network information.