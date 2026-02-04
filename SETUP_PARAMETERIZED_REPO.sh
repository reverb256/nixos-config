# Best Practices for Parameterization and Automation

## Recommended Approach: Separation of Public and Private Configuration

The best practice is to use a **hybrid approach** that separates public infrastructure patterns from private deployment values while maintaining a fully automated workflow.

## 🏗️ Architecture: Public-Private Separation Pattern

### 1. **Public Repository Structure** (`/etc/nixos/public/`)
```
public/
├── modules/
│   ├── networking.nix          # Public networking patterns  
│   ├── mining.nix              # Generic mining config structure
│   └── tailscale.nix           # Tailscale setup patterns
├── templates/
│   ├── host-config.nix         # Host configuration template
│   └── secrets-template.age    # Encrypted secrets template
├── flake.nix                   # Public flake with interface specifications
└── examples/
    ├── example-cluster.nix     # Example configuration
    └── docs/
        └── parameters.md       # Documentation of parameters
```

### 2. **Private Configuration** (`/etc/nixos/private/` - NOT in public repo)
```
private/
├── secrets/
│   ├── node-credentials.age    # Host-specific encrypted credentials
│   └── network-config.age      # Private network configuration
├── host-configs/
│   ├── zephyr.nix              # Zephyr-specific overrides
│   ├── nexus.nix               # Nexus-specific overrides
│   ├── forge.nix               # Forge-specific overrides
│   └── sentry.nix              # Sentry-specific overrides
├── cluster-config.nix          # Cluster-specific settings
└── secrets.nix                 # Agenix configuration
```

### 3. **Integration Layer** (`/etc/nixos/flake.nix` - Main flake)
```nix
{
  inputs = {
    # Public infrastructure patterns
    nixos-public.url = "path:./public";
    
    # Other inputs...
  };
  
  outputs = { self, nixos-public, ... }@inputs: let
    # Import private configuration
    privateConfig = import ./private/cluster-config.nix;
    
    # Public configuration with private values overlayed
    mkHost = hostname: {
      imports = [
        nixos-public.nixosModules.default
        ./private/host-configs/${hostname}.nix
      ];
    };
  in {
    nixosConfigurations = {
      zephyr = mkHost "zephyr";
      nexus = mkHost "nexus"; 
      forge = mkHost "forge";
      sentry = mkHost "sentry";
    };
  };
}
```

## 🛠️ Parameterization System

### 1. **Public Module Interface** (`public/modules/networking.nix`)
```nix
{ config, lib, pkgs, ... }: let
  cfg = config.services.cluster-networking;
in {
  options.services.cluster-networking = {
    # Public parameters with documentation
    internalNetwork = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.0/24";  # Dummy for public repo
      description = "Internal cluster network CIDR";
      example = "10.1.1.0/24";
    };
    
    nodes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          ip = lib.mkOption {
            type = lib.types.str;
            description = "Node IP address";
            example = "10.1.1.110";
          };
          hostname = lib.mkOption {
            type = lib.types.str;
            description = "Node hostname";
            example = "zephyr";
          };
          tailscaleIP = lib.mkOption {
            type = lib.types.str;
            description = "Tailscale IP address";
            example = "100.81.182.5";
          };
        };
      });
      description = "Cluster node configurations";
    };
    
    # Mining configuration
    mining = {
      wallets = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "Mining wallet addresses per node";
        default = {};
        example = { zephyr = "dummy-wallet-ids"; };
      };
    };
  };
  
  config = lib.mkIf (cfg.internalNetwork != "192.168.1.0/24") {
    # Only configure if not using dummy public values
    networking = {
      # Configuration using private values
    };
  };
}
```

### 2. **Private Configuration** (`private/host-configs/zephyr.nix`)
```nix
{ config, lib, pkgs, ... }: {
  services.cluster-networking = {
    internalNetwork = "10.1.1.0/24";
    nodes = {
      zephyr = {
        ip = "10.1.1.110";
        hostname = "zephyr";
        tailscaleIP = "100.81.182.5";
      };
      nexus = {
        ip = "10.1.1.120";
        hostname = "nexus";
        tailscaleIP = "100.86.158.18";
      };
      # ... other nodes
    };
    mining.wallets = {
      zephyr = "krxXVNVMM7.zephyr";
      # ... other wallets
    };
  };
  
  networking.hostName = "zephyr";
  # Other host-specific private config
}
```

## 🤖 Automation System

### 1. **Automated Template Generation Script**
```nix
# public/scripts/generate-template.nix
{ inputs, ... }: {
  packages.x86_64-linux = rec {
    generatePublicTemplates = inputs.nixpkgs.legacyPackages.x86_64-linux.writeShellApplication {
      name = "generate-templates";
      text = ''
        # Generate public templates with dummy values
        mkdir -p generated-public/{modules,hosts,docs}
        
        # Process each module file to replace private values with public examples
        for file in $INPUT_MODULES/*.nix; do
          sed \
            -e 's/10\.1\.1\.[0-9]\+/192.168.1.X/g' \
            -e 's/100\.[0-9]\+\.[0-9]\+\.[0-9]\+/100.YYY.YYY.YYY/g' \
            -e 's/krxXVNVMM7\.[a-z]*$/DUMMY-WALLET-ID/g' \
            -e 's/"zephyr"\|"nexus"\|"forge"\|"sentry"/"NODE-NAME"/g' \
            "$file" > "generated-public/modules/$(basename "$file")"
        done
        
        echo "Public templates generated successfully"
      '';
    };
  };
}
```

### 2. **Automated Build Verification**
```nix
# flake.nix outputs
{
  # ... other outputs
  
  checks.x86_64-linux = {
    # Public config should still build with dummy values
    public-build-test = nixpkgs.lib.nixosSystem {
      modules = [
        ./public/modules
        {
          # Public test configuration with dummy values
          services.cluster-networking.internalNetwork = "192.168.1.0/24";
          services.cluster-networking.nodes = {};
        }
      ];
    };
    
    # Private config with real values should also build
    private-build-test = nixpkgs.lib.nixosSystem {
      modules = [
        ./public/modules
        ./private/cluster-config.nix
      ];
    };
  };
}
```

### 3. **Automated Deployment Safety**
```bash
# scripts/validate-private-config.sh
#!/usr/bin/env bash

# Ensure no private data is in the public part
validate_public_safety() {
    local error_found=0
    
    # Check for private IP ranges in public files
    if git grep -r "10\.1\.1\." public/ 2>/dev/null; then
        echo "ERROR: Private IPs found in public directory"
        error_found=1
    fi
    
    if git grep -r "krxXVNVMM7\." public/ 2>/dev/null; then
        echo "ERROR: Mining wallets found in public directory"
        error_found=1
    fi
    
    # Validate hostnames
    if git grep -rE "(zephyr|nexus|forge|sentry)" public/*.nix 2>/dev/null; then
        echo "ERROR: Hostnames found in public directory"
        error_found=1
    fi
    
    return $error_found
}

validate_private_inclusion() {
    local private_vars_missing=0
    
    # Check that private config provides required values
    if ! grep -q "10\.1\.1\." private/cluster-config.nix; then
        echo "WARNING: Private network config may be missing"
        private_vars_missing=1
    fi
    
    return $private_vars_missing
}

if validate_public_safety && validate_private_inclusion; then
    echo "Validation passed!"
    exit 0
else
    echo "Validation failed!"
    exit 1
fi
```

## 🔄 GitHub Actions Automation

```yaml
# .github/workflows/validation.yml
name: Config Validation

on:
  push:
    branches: [ main ]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@v4

      - name: Validate Public Safety
        run: |
          ./scripts/validate-private-config.sh

      - name: Test Public Build
        run: |
          nix flake check --override-input nixosConfigurations.public-check ./public/checks.nix

      - name: Test Private Build
        run: |
          nix build .#nixosConfigurations.zephyr.config.system.build.toplevel --no-link
```

## 📁 Complete Implementation Template

I'll create a script to set up this configuration pattern:

```bash
#!/usr/bin/env bash
# setup-parameterized-repo.sh

set -e

echo "Setting up parameterized NixOS configuration..."

# Create directory structure
mkdir -p public/{modules,templates,examples}
mkdir -p private/{secrets,host-configs}

# Move current public configs to public/
find . -name "*.nix" -not -path "./private/*" -not -path "./scripts/*" -exec mv {} public/modules/ \; 2>/dev/null || true

# Create parameterized version of a sample module
cat > public/modules/cluster-networking.nix << 'EOF'
{ config, lib, pkgs, ... }: let
  cfg = config.cluster.networking;
in {
  options.cluster.networking = {
    internalCIDR = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.0/24";  # Dummy for public repo
      description = "Internal network CIDR (change for private deployment)";
    };
    
    nodes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          ip = lib.mkOption {
            type = lib.types.str;
            description = "Node IP address";
          };
          hostname = lib.mkOption {
            type = lib.types.str;
            description = "Node hostname";
          };
          tailscaleIP = lib.mkOption {
            type = lib.types.str;
            description = "Tailscale IP";
          };
        };
      });
      description = "Cluster node configurations";
    };
  };
  
  config = lib.mkIf (cfg.internalCIDR != "192.168.1.0/24") {
    networking = {
      interfaces = lib.mapAttrs' (name: node: {
        name = "enp38s0";  # Example interface
        value = {
          ipv4.addresses = [{
            address = node.ip;
            prefixLength = 24;
          }];
        };
      }) cfg.nodes;
    };
  };
}
EOF

# Create example private config
cat > private/host-configs/zephyr.nix << 'EOF'
{
  cluster.networking = {
    internalCIDR = "10.1.1.0/24";
    nodes = {
      zephyr = {
        ip = "10.1.1.110";
        hostname = "zephyr";
        tailscaleIP = "100.81.182.5";
      };
      nexus = {
        ip = "10.1.1.120";
        hostname = "nexus";
        tailscaleIP = "100.86.158.18";
      };
      forge = {
        ip = "10.1.1.130";
        hostname = "forge";
        tailscaleIP = "100.116.190.124";
      };
      sentry = {
        ip = "10.1.1.140";
        hostname = "sentry";
        tailscaleIP = "100.82.210.39";
      };
    };
  };
}
EOF

# Update flake.nix to use the new structure
cat > flake.nix << 'EOF'
{
  description = "Parameterized NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    agenix.url = "github:ryantm/agenix";
  };

  outputs = { self, nixpkgs, home-manager, agenix, ... }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    
    # Load private configuration
    privateConfig = import ./private/cluster-config.nix or {};
    
    # Build configuration for each host
    mkHost = hostname: {
      imports = [
        ./public/modules/cluster-networking.nix
        ./private/host-configs/${hostname}.nix
      ];
      # Other common configuration
    };
  in {
    nixosConfigurations = {
      zephyr = mkHost "zephyr";
      nexus = mkHost "nexus";
      forge = mkHost "forge";
      sentry = mkHost "sentry";
    };
    
    checks = {
      # Public config validation with dummy values
      public-validation = nixpkgs.lib.nixosSystem {
        modules = [
          ./public/modules/cluster-networking.nix
          {
            cluster.networking.internalCIDR = "192.168.1.0/24";
            cluster.networking.nodes = {};
          }
        ];
      };
    };
  };
}
EOF

# Create safety validation script
cat > scripts/validate-public-safe.sh << 'EOF'
#!/usr/bin/env bash
set -e

echo "Validating that no private data is in public directory..."

# Check for private patterns in public directory
PRIVATE_PATTERNS=(
    "10\.1\.1\.[0-9]{1,3}"
    "100\.[0-9]+\.[0-9]+\.[0-9]+"
    "krxXVNVMM7\."
    "zephyr\|nexus\|forge\|sentry"
)

for pattern in "${PRIVATE_PATTERNS[@]}"; do
    if find public/ -name "*.nix" -exec grep -l "$pattern" {} \; 2>/dev/null; then
        echo "ERROR: Found private data matching pattern: $pattern"
        exit 1
    fi
done

echo "✓ No private data found in public directory"
EOF

chmod +x scripts/validate-public-safe.sh

echo "Parameterized repository structure created!"
echo ""
echo "Next steps:"
echo "1. Review public/modules/ for sensitive data"
echo "2. Add private/ to .gitignore"
echo "3. Update private/host-configs/* with your real values"
echo "4. Test the configuration: nix flake check"
echo "5. Add validation script to git hooks"