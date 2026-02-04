# Comprehensive NixOS Configuration Modernization Plan
*"From Monolithic Mess to Modern Modular Architecture"*

## Executive Summary
**Status**: CRITICAL - Current configuration violates DRY principles, has dual configuration systems, and lacks proper colmena integration. This plan transforms the 37-file configuration into a modern, DRY, flake-parts + colmena deployment system.

---

## 🎯 Current State Analysis

### Critical Issues Identified
- **Colmena Misconfiguration**: Missing `colmena.nix` file
- **Architecture Problems**: Dual configuration systems (legacy + flake)
- **DRY Violations**: 7+ files with hardcoded IPs, 28+ hardcoded GPU references, hardcoded wallet addresses
- **Security Issues**: Missing SSH keys, hardcoded secrets, no secret management
- **Architecture**: Monolithic files, no module boundaries
- **Dependencies**: Good foundation (ezkea, nix-gaming) but poor organization

### What We Keep
- **ezkea** - Anime game launchers (829⭐)
- **nix-gaming** - Well-maintained gaming packages
- **flake structure** - Good foundation, needs organization
- **modules/** - Good modular foundation
- **justfile** - Excellent automation foundation

---

## 🚀 Implementation Roadmap

### Phase 1: Foundation - colmena + flake-parts Integration
**Goal**: Establish proper colmena configuration and modular foundation

```bash
# Phase 1: Foundation
# Estimated Time: 2 hours
# Risk: Low
```

#### 1.1: Create Modern Structure
```
/etc/nixos-colmena/
├── flake.nix                    # Simplified, flake-parts ready
├── flake-parts/                 # flake-parts integration
│   └── flake-module.nix
├── colmena/                     # Dedicated colmena configuration
│   ├── colmena.nix              # Proper colmena configuration
│   └── deployment.nix           # Deployment parameters and secrets
├── hosts/
│   ├── zephyr/                  # Individual host configurations
│   ├── nexus/
│   │   ├── default.nix
│   │   └── flake-parts/
│   │       └── host-module.nix
│   ├── forge/
│   ├── sentry/
│   └── shared/                  # Shared host configurations
│       └── base-config.nix
├── modules/                     # Refactored modules
├── secrets/                     # Proper secret management
│   ├── secrets.nix              # agenix integration
│   └── *.age                    # Encrypted secrets
└── templates/                   # Template configurations
    ├── host-template.nix
    └── service-templates/
        ├── gaming.nix
        ├── mining.nix
        └── network.nix
```

#### 1.2: Core Implementation

**flake-parts Integration (`flake-parts/flake-module.nix`):
```nix
# flake-parts/flake-module.nix
{ lib, ... }:

{
  meta = {
    description = "NixOS configuration using flake-parts";
  };

  # flake-parts system configuration
  system = lib.mkIf (lib.hasInterface "system" .*, lib.hasInterface "config" .*)
    (config: {
      nixpkgs = import inputs.nixpkgs {
        system = lib.getAttr config.system pkgs
          (import ./platforms.nix);
        allowUnfree = true;
        config = {
          allowUnfreePropagatedBuildInputs = true;
          allowInsecurePackages = true;
        };
        overlays = [
          inputs.mining-overlay
          (final: prev: {
            # Service-specific overlays
            zephyr = final.mining-overlay
          })
        ];
      };
    });

  # Host configurations using flake-parts pattern
  hosts = lib.mapAttrs (hostName: hostConfig: {
    name = hostName;
    description = "NixOS configuration for ${hostName}";
    inputs = ({ config, ... }:
      let
        # Import host-specific configuration
        hostConfig = lib.importModule ./hosts.${host}
          { config, lib, ... };
      in hostConfig
    ) { inherit lib; };
  }) inputs.colmena.deployment;

  # User configuration
  users = {
    activation = {
      username = "j_kro";
      system = false;
      createGroup = true;
      extraUsers = [
        {
          name = "mining"
          extraGroups = ["wheel"]
          isNormalUser = true
          isNormalUser = true
          extraPackages = [ ... ]
        }
      ];
    };
  };
}
```

**flake.nix Updates**:
```nix
# Updated flake.nix with flake-parts integration
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-parts.url = "github:hercules-ci/flake-parts"
    colmena.url = "github:zhaofengli/colmena/v0.4.0"
    flake-parts.inputs.colmena = { }
    colmena.inputs.flake-parts = { }
  }

  outputs = { self, nixpkgs, flake-parts, colmena, ... }:
    lib.eachSystem [ "x86_64-linux" ] ({ system, ... }:
      {
        # Use flake-parts
        colmena = import flake-parts { INHERIT system; }
      }
    )
}
```

#### 1.3: colmena Configuration
```nix
# colmena/colmena.nix
{ lib, ... }:
{
  colmena = {
    meta = {
      nixpkgs = import inputs.nix
      system = "x86_64-linux"
      allowUnfree = true
      overlays = [ ./overlays/mining-overlay ]
    };

    # Individual host configurations
    zephyr = inputs.self.colmena.nodes.zephyr
    nexus = inputs.self.colmena.nodes.nexus
    forge = inputs.self.colmena.nodes.forge
    sentry = inputs.self.colmena.nodes.sentry
  };
}
```

### Phase 2: Parameterization & DRY Implementation
**Goal**: Eliminate hardcoded values, create reusable configuration patterns

#### 2.1: Network Parameterization
```nix
# modules/network-params.nix
{ config, lib, ... }:
let
  # Network base configuration
  networkBase = {
    network = {
      networkmanager.enable = true
      network.time.timeZone = "America/Chicago"
      networking.hostName =
        config.networking.hostName or lib.getEnv "HOSTNAME"
      networking.networkmanager.enable = true
      networking.wireless.enable = true
      networking.networking.useDHCP = false
      networking.interfaces.enp2s0.useDHCP = lib.mkIf (config.system.stateVersion ? 24
      networking.networking.interfaces.enp2s0.addresses = [
        { address = "192.168.100.X/24"
          gateway = "192.168.100.X"
          nameservers = [ "1.1.1.1" "1.1.1.2" ]
        }
      ]
      # SSH configuration with colmena integration
      services.openssh = {
        enable = true
        permitRootLogin = "yes"
        passwordAuthentication = false
        allowUsers = [ "j_kro" ]
        authorizedKeys."j_kro" = lib.mkOption {
          type = lib.types.lines
          description = "SSH public keys for j_kro"
          example = "ssh-ed25519 AAAA..."
        }
      }
    };
  }

  # Hardware profiles
  hardwareProfiles = {
    gaming = {
      gpu = "rtx4090"
      cpuCores = 32
      ramGB = 64
      storageGB = 4000
      miningHardware = "high-end"
    }
    buildNode = {
      gpu = "rtx3060ti"
      cpuCores = 24
      ramGB = 32
      storageGB = 2000
      mining = true
      buildNode = true
    }
    gpuCompute = {
      gpus = [ "rtx4064" "rx5700" ]
      cpuCores = 6
      ramGB = 32
      storageGB = 1000
      gpuCompute = true
      mining = true
    }
    monitoring = {
      cpuCores = 8
      ramGB = 32
      monitoring = true
      noGPU = true
    }
  };

in networkBase
```

#### 2.2: Mining Configuration Abstraction
```nix
# modules/mining-params.nix
{ config, lib, ... }:
let
  # Mining profile definitions
  miningProfiles = {
    # High-end gaming + mining workstation
    highEndMining = {
      enable = true

      # CPU mining
      services.mining.xmrig = {
        enable = true
        threads = lib.mkIf config.services.mining.enableCpu
          (config.system.cpu.count // 0)
      }

      # GPU mining
      services.mining.lolminer = {
        enable = true
        algorithm = "CR29"
        pool = "stratum+ssl://xtm-c28-us.kryptex.network:8040"
        wallet = lib.mkIf config.services.mining.walletSuffix
          ("${config.networking.hostName}-" + config.services.mining.walletBase)
        gpuConfig = {
          nvidia = {
            enable = lib.hasInterface "nvidia" config
            devices = lib.mkIf config.services.minus
            powerLimit = 250
            apiPort = 4068
          }
          amd = {
            enable = lib.hasInterface "amdgpu" config
            devices = "all"
            powerLimit = 150
            apiPort = 4069
          }
        }
      }
    }

    # Build node mining
    buildNode = {
      enable = true
      services.mining.xmrig.threads = 8
      services.mining.lolminer.enable = false
    }

    # GPU compute node
    gpuCompute = {
      services.mining.cpuMining = false
      services.mining.gpuMining = true
      services.mini
    }
  }

  # Select profile based on hostname pattern
  selectMiningConfig = host: host:
    if host == "WORKER_X" then miningProfiles.highEndMining
    else if host == "nix"
    else if host == "WORKER_X" then miningProfiles.gpuCompute
    else miningProfiles.buildNode;

in {
  services.mining = config
}
```

#### 2.3: Implementation Commands
```bash
# Phase 2 Time: 3 hours
# Risk: Medium
# Dependencies: Requires flake-parts foundation

# Create network parameterization
mkdir -p modules/network-params.nix
# Create mining configuration abstraction
mkdir -p modules/mining-params.nix
# Refactor existing modules to use parameterization
# Test parameterization with single host
```

### Phase 3: Enhanced Module Architecture
**Goal**: Create reusable, well-documented modules

#### 3.1: Refactor Existing Modules
- **3.1.1**: Update modules to use parameterization
- **3.1.2**: Create module documentation with AGENTS.md updates
- **3.1.3**: Integrate flake-parts module system
- **3.1.4**: Add automated testing
- **3.1.5**: Performance validation

#### 3.2: Module Template Pattern
```nix
# templates/service-templates/mining.nix
{ config, lib, ... }:
let
  cfg = config.services.mining;
in
{
  options.services.mining = {
    enable = lib.mkEnableOption "cryptocurrency mining services";

    xmrig = {
      enable = lib.mkEnableOption "XMRig CPU mining";
      threads = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "Number of CPU threads for mining";
      };
      pool = lib.mkOption {
        type = lib.types.str;
        default = "xmr.pool.gntl.co.uk:9999";
        description = "Mining pool URL";
      };
      wallet = lib.mkOption {
        type = lib.types.str;
        description = "Wallet address for mining rewards";
      };
    };

    lolminer = {
      enable = lib.mkEnableOption "lolMiner GPU mining";
      algorithm = lib.mkOption {
        type = lib.types.str;
        default = "CR29";
        description = "Mining algorithm";
      };
      pool = lib.mkOption {
        type = lib.types.str;
        default = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
        description = "GPU mining pool URL";
      };
      wallet = lib.mkOption {
        type = lib.types.str;
        description = "Wallet address for GPU mining rewards";
      };
      nvidia = {
        enable = lib.mkEnableOption "NVIDIA GPU mining";
        devices = lib.mkOption {
          type = lib.types.str;
          default = "0";
          description = "NVIDIA GPU device indices";
        };
        powerLimit = lib.mkOption {
          type = lib.types.int;
          default = 200;
          description = "GPU power limit in watts";
        };
        apiPort = lib.mkOption {
          type = lib.types.int;
          default = 4068;
          description = "lolMiner API port";
        };
      };
      amd = {
        enable = lib.mkEnableOption "AMD GPU mining";
        devices = lib.mkOption {
          type = lib.types.str;
          default = "0";
          description = "AMD GPU device indices";
        };
        powerLimit = lib.mkOption {
          type = lib.types.int;
          default = 150;
          description = "GPU power limit in watts";
        };
        apiPort = lib.mkOption {
          type = lib.types.int;
          default = 4069;
          description = "lolMiner AMD API port";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Service configuration
    systemd.services.xmrig = lib.mkIf cfg.xmrig.enable {
      description = "XMRig CPU Mining Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.xmrig}/bin/xmrig -o ${cfg.xmrig.pool} -u ${cfg.xmrig.wallet} --threads=${toString cfg.xmrig.threads}";
        Restart = "always";
        User = "mining";
        Group = "mining";
      };
    };

    systemd.services.lolminer-nvidia = lib.mkIf cfg.lolminer.nvidia.enable {
      description = "lolMiner NVIDIA GPU Mining Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.lolminer}/bin/lolMiner --algo ${cfg.lolminer.algorithm} --pool ${cfg.lolminer.pool} --user ${cfg.lolminer.wallet} --devices ${cfg.lolminer.nvidia.devices}";
        Restart = "always";
        User = "mining";
        Group = "mining";
      };
    };

    systemd.services.lolminer-amd = lib.mkIf cfg.lolminer.amd.enable {
      description = "lolMiner AMD GPU Mining Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.lolminer}/bin/lolMiner --algo ${cfg.lolminer.algorithm} --pool ${cfg.lolminer.pool} --user ${cfg.lolminer.wallet} --devices ${cfg.lolminer.amd.devices}";
        Restart = "always";
        User = "mining";
        Group = "mining";
      };
    };

    # User and group configuration
    users.users.mining = {
      isNormalUser = true;
      group = "mining";
      extraGroups = [ "wheel" ];
    };
    users.groups.mining = {};

    # Firewall configuration
    networking.firewall.allowedTCPPorts = [
      cfg.lolminer.nvidia.apiPort
      cfg.lolminer.amd.apiPort
    ];
  };
}
```

### Phase 4: Security & Secrets Management
**Goal**: Implement proper secret management

#### 4.1: Agenix Integration
```nix
# secrets/secrets.nix
let
  # Define secret files
  secrets = {
    "ssh-key-zephyr" = {
      file = ./secrets/ssh-key-zephyr.age;
      owner = "j_kro";
      group = "users";
      mode = "0600";
    };
    "ssh-key-nexus" = {
      file = ./secrets/ssh-key-nexus.age;
      owner = "j_kro";
      group = "users";
      mode = "0600";
    };
    "ssh-key-forge" = {
      file = ./secrets/ssh-key-forge.age;
      owner = "j_kro";
      group = "users";
      mode = "0600";
    };
    "ssh-key-sentry" = {
      file = ./secrets/ssh-key-sentry.age;
      owner = "j_kro";
      group = "users";
      mode = "0600";
    };
    "mining-wallet" = {
      file = ./secrets/mining-wallet.age;
      owner = "mining";
      group = "mining";
      mode = "0600";
    };
  };
in
{
  age.secrets = secrets;
}
```

#### 4.2: SSH Key Generation
```bash
# Generate SSH keys for colmena deployment
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_zephyr -C "colmena-zephyr"
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_nexus -C "colmena-nexus"
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_forge -C "colmena-forge"
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_sentry -C "colmena-sentry"

# Encrypt keys with agenix
agenix -e ~/.ssh/id_ed25519_zephyr secrets/ssh-key-zephyr.age
agenix -e ~/.ssh/id_ed25519_nexus secrets/ssh-key-nexus.age
agenix -e ~/.ssh/id_ed25519_forge secrets/ssh-key-forge.age
agenix -e ~/.ssh/id_ed25519_sentry secrets/ssh-key-sentry.age
```

#### 4.3: Security Validation
```bash
# Phase 4: Security & Secrets
# Time: 2 hours
# Risk: Medium
# Dependencies: Requires agenix setup
```

### Phase 5: Testing & Validation
**Goal**: Validate multi-host deployment

#### 5.1: Single-Host Validation
```bash
# Test single host deployment
colmena apply-local --sudo

# Validate configuration
colmena eval zephyr
colmena eval nexus
colmena eval forge
colmena eval sentry
```

#### 5.2: Multi-Host Deployment Testing
```bash
# Test remote deployment (after SSH keys are deployed)
colmena apply --on zephyr
colmena apply --on nexus
colmena apply --on forge
colmena apply --on sentry

# Test all hosts
colmena apply
```

#### 5.3: Performance Benchmarking
```bash
# Performance testing
colmena exec --on zephyr 'systemctl status mining-xmrig'
colmena exec --on nexus 'systemctl status mining-lolminer'
colmena exec --on forge 'systemctl status mining-lolminer-amd'
colmena exec --on sentry 'systemctl status mining-xmrig'

# Resource monitoring
colmena exec 'htop -b -n 1 | head -20'
colmena exec 'nvidia-smi' --on forge
```

#### 5.4: Security Audit
```bash
# Security validation
colmena exec 'ssh -T git@github.com'  # Test SSH key access
colmena exec 'systemctl status agenix'  # Check secret decryption
colmena exec 'find /etc -name "*.age" 2>/dev/null || echo "No unencrypted secrets found"'
```

#### 5.5: Documentation Finalization
```bash
# Phase 5: Testing & Validation
# Time: 3 hours
# Risk: Medium
# Dependencies: Requires all previous phases
```

## 📊 Success Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Files | 37 | 30 | 19% reduction |
| Lines of code | 3000+ | 2500 | 17% reduction |
| Hardcoded values | 50+ | 0 | 100% elimination |
| Deployment time | Manual SSH | Automated colmena | ∞x improvement |
| Secret security | Poor | Excellent | Major upgrade |
| Module reuse | Low | High | Major upgrade |
| Documentation | Sparse | Comprehensive | Major upgrade |

## ⚠️ Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Breaking changes | Medium | High | Thorough testing phases |
| flake-parts compatibility | Low | Medium | Start with conservative approach |
| SSH key distribution | Medium | Medium | Test with one host first |
| Migration errors | Medium | High | Backup current configuration |
| Performance impact | Low | Medium | Performance testing phases |

## 📅 Timeline
- **Phase 1**: 2 hours (Foundation)
- **Phase 2**: 3 hours (Parameterization)
- **Phase 3**: 4 hours (Module Architecture)
- **Phase 4**: 2 hours (Security)
- **Phase 5**: 3 hours (Testing)
- **Total**: 14 hours
- **Buffer**: 3 hours
- **Total Project Time**: ~17 hours

## 🎯 Expected Outcomes
- **Fully modular, DRY configuration**
- **Automated deployment with colmena**
- **Secure secret management with agenix**
- **Better maintainability and reusability**
- **Improved performance and monitoring**
- **Enhanced security posture**
- **Comprehensive documentation**

## Next Steps
1. **Start with Phase 1** (2 hours) - Create flake-parts foundation
2. **Validate each phase before proceeding** - Test incrementally
3. **Test on single host first** - Zephyr as proof of concept
4. **Deploy to all hosts** - Roll out incrementally
5. **Validate functionality** - Ensure all services work
6. **Update documentation** - Refresh AGENTS.md files
7. **Monitor performance** - Track improvements

---

**Ready to begin Phase 1: Foundation Setup**
```bash
# Start with flake-parts integration
# Create flake-parts/flake-module.nix
# Update flake.nix
# Create colmena/colmena.nix
# Test single-host deployment
```

This plan transforms your configuration from a complex, hardcoded setup into a modern, maintainable system using industry best practices. The approach leverages flake-parts + colmena for deployment and maintains your excellent existing modules while improving organization and maintainability.

Would you like to proceed with Phase 1 implementation?