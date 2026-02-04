# Key Architectural Patterns and Design Decisions

## 1. Module Design Patterns

### The "Option-Definition + Conditional-Config" Pattern
**Most Common Pattern**: Every module follows this consistent structure:

```nix
# Option Definition
options.services.mining = {
  enable = mkEnableOption "Mining Services";
  # Nested options with mkOption
};

# Conditional Configuration  
config = mkIf cfg.enable {
  systemd.services = { ... };
};
```

**Why It Works**: 
- Clean separation of interface from implementation
- Lazy evaluation prevents unnecessary configuration
- Consistent across all 23 modules

### The "Service-Generator" Pattern
**Advanced Pattern**: Used in mining module for multiple similar services:

```nix
# Generic service generator
lolminerWrapper = pkgs.writeShellScriptBin "lolminer-wrapper" ''
  NVIDIA_OPENCL="${nvidiaLibPath}/libnvidia-opencl.so"
  # Common wrapper logic
  exec ${pkgs.lolminer}/bin/lolMiner "$@"
'';

# Multiple service variants from single template
systemd.services.lolminer-nvidia = { ... };
systemd.services.lolminer-amd = { ... };
```

**Benefits**: 
- Eliminates code duplication
- Centralized wrapper logic
- Easy to add new mining backends

### The "Slice-Based Resource Isolation" Pattern
**Performance Pattern**: Workload isolation through systemd slices:

```nix
systemd.slices = {
  "gaming.slice" = {
    sliceConfig = {
      MemoryHigh = "90%";
      CPUQuota = "95%";
    };
  };
  "mining.slice" = {
    sliceConfig = {
      MemoryHigh = "50%";
      CPUQuota = "60%";
    };
  };
};
```

**Impact**: 
- Gaming gets priority over mining
- Prevents resource contention
- Automatic load balancing

## 2. Package Management Patterns

### The "Steam-Run Wrapper" Pattern
**Workaround Pattern**: For binaries that don't work natively:

```nix
lolminerWrapper = pkgs.writeShellScriptBin "lolminer-wrapper" ''
  export LD_LIBRARY_PATH="${nvidiaLibPath}:$LD_LIBRARY_PATH"
  exec ${pkgs.steam-run}/bin/steam-run ${pkgs.lolminer}/bin/lolMiner "$@"
'';
```

**Why Necessary**: 
- Mining binaries use non-Nix FHS paths
- steam-run provides FHS compatibility
- Better than maintaining custom FHS env

### The "Overlay Extension" Pattern
**Package Modification Pattern**: Customizing existing packages:

```nix
# In mining-overlay.nix
wivrn = prev.wivrn.overrideAttrs (old: {
  cmakeFlags = old.cmakeFlags ++ [
    "-DWIVRN_FEATURE_STEAMVR_LIGHTHOUSE=ON"
  ];
});
```

**Advantages**:
- Inherits upstream package maintenance
- Adds only necessary modifications
- Updates automatically with upstream

## 3. Configuration Patterns

### The "Centralized Package List" Pattern
**Single Source of Truth Pattern**:

```nix
# ONLY location for system packages
environment.systemPackages = with pkgs; [
  # 150+ packages in one list
];
```

**Enforced by Convention**:
- Anti-pattern to add packages elsewhere
- Prevents duplication and conflicts
- Easy dependency management

### The "Multi-Host Flake" Pattern
**Cluster Management Pattern**:

```nix
outputs = inputs @ { ... }: {
  # Shared overlays
  overlays.mining-overlay = import ./modules/mining-overlay.nix;
  
  # Multi-host deployment
  colmena = {
    meta = { nixpkgs = import inputs.nixpkgs { ... }; };
    zephyr = ./hosts/zephyr/configuration.nix;
    nexus = ./hosts/nexus/configuration.nix;
  };
  
  # Per-host configurations
  nixosConfigurations.zephyr = nixpkgs.lib.nixosSystem { ... };
};
```

**Benefits**:
- Single command deploys to all hosts
- Shared state across cluster
- Consistent build environments

## 4. Performance Optimization Patterns

### The "Resolution-Specific Tuning" Pattern
**Gaming Optimization**: Separate optimization profiles:

```nix
systemd.services."vr-90hz-optimization" = {
  ExecStart = ''
    nvidia-settings -a "GPUGraphicsClockOffset[3:0]=150"
  '';
};
systemd.services."4k-60hz-optimization" = { ... };
systemd.services."1440p-120hz-optimization" = { ... };
```

**Rationale**:
- Different refresh rates need different overclocks
- Prevents over/under-clocking for specific use cases
- Can be started/stopped per gaming session

### The "Smart Mining Pause" Pattern
**Resource Competition Solution**:

```nix
# In gaming module
ExecStop = "${pkgs.systemctl}/bin/systemctl stop mining.service";

# Health monitoring
miner-monitor = mkIf cfg.lolminer.enable {
  script = "${monitorScript}/bin/miner-monitor";
};
```

**How It Works**:
- Gaming services automatically pause mining
- Health checks resume when gaming stops
- No manual intervention needed

## 5. Security Patterns

### The "Analytics Blocking" Pattern
**Privacy Protection**:

```nix
networking.extraHosts = ''
  # VRChat Analytics Blocklist
  0.0.0.0 api.amplitude.com
  0.0.0.0 api2.amplitude.com
  0.0.0.0 api.lab.amplitude.com
  # ... 18+ domains blocked
'';
```

**Effectiveness**:
- Prevents telemetry at DNS level
- Works regardless of application settings
- Easy to maintain with external blocklists

### The "Multi-Tier DNS" Pattern
**Performance + Security**:

```nix
services.unbound = {
  forward-zone = [{
    name = ".";
    forward-addr = [
      "9.9.9.9@853#dns.quad9.net"    # Quad9 (privacy-focused)
      "8.8.8.8@853#dns.google"       # Google (reliability)
      "1.1.1.1@853#cloudflare-dns.com" # Cloudflare (speed)
    ];
    forward-tls-upstream = true;
  }];
};
```

**Benefits**:
- DNS over TLS prevents interception
- Multiple providers for redundancy
- Local caching improves performance

## 6. Development Patterns

### The "Justfile Automation" Pattern
**Operational Excellence**: 25+ commands for cluster management:

```makefile
just switch              # Rebuild and switch system
just cluster-deploy      # Deploy to all hosts  
just mining-start        # Start mining services
just gaming-start        # Enable gaming optimizations
```

**Why Justfile**:
- Better than Make for shell commands
- Easy to learn and extend
- Cross-platform compatibility

### The "Health Monitoring" Pattern
**Service Reliability**:

```nix
monitorScript = pkgs.writeShellScriptBin "miner-monitor" ''
  API_RESPONSE=$(curl -s http://localhost:4068/summary)
  if [[ -z "$API_RESPONSE" ]]; then
    systemctl restart lolminer-nvidia
  fi
'';
systemd.timers.miner-monitor = {
  OnUnitActiveSec = "5m";
};
```

**Features**:
- Automatic recovery from failures
- Regular health checks
- Minimal manual intervention

## Pattern Evolution

### Current Maturity Level
The codebase shows **intermediate to advanced** NixOS pattern usage:

1. **Basic patterns mastered**: option definitions, mkIf guards
2. **Intermediate patterns implemented**: service generators, overlays  
3. **Advanced patterns explored**: multi-host flakes, performance tuning
4. **Areas for improvement**: security hardening, secret management

### Pattern Trade-offs
Each pattern represents conscious design decisions:
- **Convenience vs Security**: Passwordless sudo for mining controls
- **Performance vs Complexity**: Resolution-specific optimizations  
- **Features vs Maintainability**: Large modules with multiple concerns
- **Compatibility vs Purity**: steam-run wrappers vs proper packaging

These patterns demonstrate sophisticated NixOS usage while maintaining practical usability for a gaming/mining focused system.