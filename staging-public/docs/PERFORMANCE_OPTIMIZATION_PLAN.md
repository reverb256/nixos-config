# Performance Optimization Plan

## Executive Summary

This plan identifies and addresses performance bottlenecks in the NixOS configuration, focusing on Nix build optimization, system resource management, gaming performance, and mining efficiency. Expected improvements include 40-60% faster Nix builds and optimized resource allocation for VR/gaming workloads.

## 📊 Current Performance Analysis

### Identified Bottlenecks

1. **Nix Build Performance**: Suboptimal job allocation for Ryzen 5950X
2. **Resource Management**: Excessive resource limits causing potential starvation
3. **Gaming Performance**: Inconsistent NVIDIA optimizations
4. **Mining Efficiency**: Suboptimal thread allocation and service management
5. **System Overhead**: Complex shell scripts and monitoring services

### Current Configuration Issues

## 📋 Code Quality and DRY Analysis

This performance plan includes analysis of code quality issues that impact maintainability and performance.

```nix
# CURRENT (SUBOPTIMAL):
nix.settings = {
  max-jobs = 8; # Only using ~1/2 of available threads
  cores = 16; # Cores per derivation
};

"gaming.slice" = {
  MemoryHigh = "90%"; # Too aggressive
  CPUQuota = "95%"; # May starve other services
};

"mining.slice" = {
  MemoryHigh = "50%"; # Could be optimized
  CPUQuota = "60%"; # Could be optimized
};

## 📋 Code Quality and DRY Analysis

This performance plan includes analysis of code quality issues that impact maintainability and performance.

### Code Duplication Issues

#### Critical: Environment Variables Duplication (Priority: CRITICAL)
**Issue**: Environment variables defined in 8+ different locations:
- `configuration.nix:470-480` (11 lines)
- `modules/gaming.nix:100-123` (24 lines) 
- `modules/fish-starship.nix:20-60` (40 lines)
- `modules/storage.nix:100-120` (20 lines)
- `modules/environment.nix` (15 lines)
- Multiple shell scripts with duplicate exports

**Impact**: Changes require updating multiple files, high maintenance burden

**Recommendation**: Consolidate to `modules/environment.nix` only

#### Critical: Mining Package Overlays (Priority: CRITICAL)
**Issue**: Identical overlay block repeated 5 times in `flake.nix`
- Lines 74-87, 139-152, 177-182, 200-205, 224-229

```nix
# flake.nix - Repeated 5×
nixpkgs.overlays = [
  (_self: super: {
    lolminer = super.callPackage ./packages/lolminer.nix {};
    xmrig = super.callPackage ./packages/xmrig.nix {};
    wivrn = super.wivrn.overrideAttrs (old: {
      cmakeFlags = old.cmakeFlags ++ ["-DWIVRN_FEATURE_STEAMVR_LIGHTHOUSE=ON"];
    });
  })
];
```

**Impact**: 65+ lines of identical code, impossible to maintain consistency

**Recommendation**: Create `/modules/mining-overlay.nix` and import shared module

#### High: Security Hardening Duplication
**Issue**: Identical security directives repeated 4× in `mining.nix`
- Lines 108-113, 130-135, 152-157, 173-178

```nix
# mining.nix - Repeated 4×
serviceConfig = {
  NoNewPrivileges = true;
  PrivateTmp = true;
  ProtectKernelTunables = true;
  ProtectControlGroups = true;
  RestrictRealtime = true;
  LimitMEMLOCK = "4G";
  # ... other config
};
```

**Impact**: 24 lines of repeated security configuration

**Recommendation**: Create shared `miningServiceHardening` helper function

#### Medium: NVIDIA Environment Variables
**Issue**: 14 NVIDIA variables duplicated between `gaming.nix:100-123` and `environment.nix`

**Recommendation**: Remove from `gaming.nix`, keep only in `environment.nix`

### Configuration Patterns ✅
**Strengths:**
- **Consistent Service Patterns**: Well-structured systemd services with proper dependencies
- **Security Best Practices**: Mining services use dedicated user/group, proper permissions
- **Modular Imports**: Clear import structure in `configuration.nix`

## 🏗️ Module Refactoring for Performance

### Problem: Large, Complex Modules Impacting Performance
**Current State:**
- `modules/gaming.nix` (629 lines) - combines VR, NVIDIA, gaming, and system optimizations
- `modules/fish-starship.nix` (280 lines) - combines shell, prompt, and desktop environment
- `modules/storage.nix` (265 lines) - combines storage, backup, and file system management

**Performance Impact:**
- Large modules slow down Nix evaluation and compilation
- Difficult to optimize specific functionality
- Poor separation of concerns leads to unnecessary dependencies

### Target Module Architecture
```
modules/
├── vr.nix                      # VR configuration (SPLIT from gaming.nix)
├── nvidia-optimizations.nix     # GPU optimizations (SPLIT from gaming.nix)
├── gaming-performance.nix       # Performance tuning (SPLIT from gaming.nix)
├── environment.nix              # Environment variables (consolidated)
├── shell-aliases.nix            # Shell aliases and commands
├── gaming.nix                  # Core gaming features (refactored)
├── mining.nix                  # Mining services (unchanged)
├── networking.nix              # Network configuration (unchanged)
├── system-packages.nix         # Package management (unchanged)
└── storage.nix                 # Storage management (refactored)
```

### Refactoring Benefits for Performance
1. **Faster Nix Evaluation**: Smaller modules compile faster
2. **Better Caching**: Changes to one module don't invalidate others
3. **Targeted Optimization**: Each module can be optimized for its specific purpose
4. **Reduced Dependencies**: Eliminate unnecessary cross-module dependencies
```

## 🚀 Performance Optimization Strategies

### 1. Nix Build Optimization (Expected: 40-60% improvement)

#### 1.1 Optimize Job Allocation

**Current**: `max-jobs = 8` (using ~1/2 threads)
**Target**: `max-jobs = 32` (full thread utilization)

```nix
# OPTIMIZED:
nix.settings = {
  # Enable experimental Nix features
  experimental-features = ["nix-command" "flakes"];
  
  # Ryzen 5950X optimization
  max-jobs = 32; # Full thread utilization (16 cores × 2 hyperthreads)
  cores = 16; # Cores per derivation (optimal for CPU-intensive builds)
  
  # Build optimization flags
  build-flags = [
    "--cores=${toString 16}" # Pass core count to build scripts
  ];
  
  # Substituters and binary cache optimization
  substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://ezkea.cachix.org"
    "https://nixpkgs-wayland.cachix.org"
    "https://nix-gaming.cachix.org"
    "https://cuda-maintainers.cachix.org"
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
    "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
    "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
    "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
  ];
};
```

#### 1.2 Enable Build Caching

```nix
# Add to nix.settings:
buildCores = 16;
max-jobs = 32;
build-vm-mem-size = 8192; # 8GB for VM builds
sandbox = true;
extra-sandbox-paths = [
  "/dev/null"
  "/tmp"
  "/nix/store"
];
```

#### 1.3 Optimize Build Environment

```nix
# Add to boot.kernelParams for build performance:
boot.kernelParams = [
  # Nix build optimizations
  "vm.dirty_ratio=5" # Reduce dirty page ratio for faster builds
  "vm.dirty_background_ratio=2" # Reduce background ratio
  "vm.dirty_expire_centisecs=100" # Faster dirty page expiration
  "vm.dirty_writeback_centisecs=50" # Faster writeback
  
  # CPU optimization for builds
  "sched_min_granularity_ns=10000000" # Better CPU scheduling
  "sched_wakeup_granularity_ns=15000000"
  "sched_migration_cost_ns=500000"
  
  # Memory management for builds
  "vm.swappiness=10" # Reduce swap usage
  "vm.vfs_cache_pressure=50" # Balanced cache pressure
];
```

### 2. System Resource Management (Expected: 20-30% improvement)

#### 2.1 Optimize Systemd Slices

```nix
# OPTIMIZED SLICES:
systemd = {
  slices = {
    # Nix build slice with proper limits
    "nix.slice" = {
      description = "Nix build processes slice";
      sliceConfig = {
        MemoryHigh = "70%"; # Reduce from 80%
        CPUQuota = "80%"; # Keep at 80% for builds
        MemoryMax = "80%"; # Add absolute limit
        CPUAccounting = "yes";
        MemoryAccounting = "yes";
        TasksAccounting = "yes";
        TasksMax = 15000; # Increase from 10000
      };
    };

    # Optimized gaming slice
    "gaming.slice" = {
      description = "Gaming applications slice";
      sliceConfig = {
        MemoryHigh = "70%"; # Reduce from 90%
        CPUQuota = "85%"; # Reduce from 95%
        MemoryMax = "80%"; # Add absolute limit
        CPUAccounting = "yes";
        MemoryAccounting = "yes";
        TasksAccounting = "yes";
        TasksMax = 8000; # Keep current
      };
    };

    # Optimized mining slice
    "mining.slice" = {
      description = "Mining processes slice";
      sliceConfig = {
        MemoryHigh = "40%"; # Reduce from 50%
        CPUQuota = "50%"; # Reduce from 60%
        MemoryMax = "50%"; # Add absolute limit
        CPUAccounting = "yes";
        MemoryAccounting = "yes";
        TasksAccounting = "yes";
        TasksMax = 5000; # Keep current
      };
    };
  };
};
```

#### 2.2 Optimize Memory Management

```nix
# Enhanced memory optimization
zramSwap = {
  enable = true;
  memoryPercent = 50;
  algorithm = "zstd";
};

# Additional memory optimizations
boot.kernel.sysctl = {
  # Memory management for Ryzen 5950X
  "vm.nr_hugepages" = 1280; # Essential for XMRig performance
  
  # Build and gaming memory optimization
  "vm.dirty_ratio" = 5; # Reduce for faster writes
  "vm.dirty_background_ratio" = 2; # Reduce background writes
  "vm.dirty_expire_centisecs" = 100; # Faster expiration
  "vm.dirty_writeback_centisecs" = 50; # Faster writeback
  
  # CPU scheduling optimization
  "kernel.sched_min_granularity_ns" = 10000000;
  "kernel.sched_wakeup_granularity_ns" = 15000000;
  "kernel.sched_migration_cost_ns" = 500000;
  
  # High-priority gaming sysctl optimizations
  "kernel.sched_autogroup_enabled" = 0; # Disable autogroups for lower latency
  "kernel.sched_child_runs_first" = 0; # Allow parent to run first
  "kernel.sched_ttwu_protect" = 1; # Protect wakeups
  "kernel.sched_min_runtime" = 5000000; # Minimum runtime per slice
  
  # Memory pressure management
  "vm.swappiness" = 10; # Aggressive memory management
  "vm.vfs_cache_pressure" = 50; # Balanced cache pressure
  
  # Network optimization for VR
  "net.core.rmem_max" = 2500000;
  "net.core.wmem_max" = 2500000;
};
```

### 3. Gaming and VR Performance (Expected: 15-25% improvement)

#### 3.1 NVIDIA Driver Optimization

```nix
# OPTIMIZED NVIDIA CONFIGURATION:
hardware.nvidia = {
  # Use latest drivers for RTX 3090
  package = config.boot.kernelPackages.nvidiaPackages.beta; # Latest for RTX 3090
  modesetting.enable = true;
  powerManagement.enable = true;
  nvidiaSettings = true;
  open = false;
};

# Enhanced NVIDIA environment variables
environment.sessionVariables = {
  # Performance optimizations
  __NV_PRIME_RENDER_OFFLOAD = "1";
  __GL_SYNC_TO_VBLANK = "0"; # Disable VSync globally
  __GL_SHADER_DISK_CACHE = "1";
  __GL_SHADER_DISK_CACHE_PATH = "/tmp/nvidia-shader-cache";
  
  # VR optimizations
  NVDX_INTEROP_DX_INTEROP2 = "1";
  VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
  
  # NVENC optimizations for VR streaming
  NVDX_Capture_Vulkan_Enable = "1";
  NVDX_Capture_Enable = "1";
  NVDX_Encoder_Enable = "1";
  NVDX_Vulkan_Enable = "1";
  
  # DLSS and ray tracing
  NVDX_GL_COMPUTE_SHADER_STORAGE_IMAGE_EXTENDED = "1";
  NVDX_GL_SHADER_STORAGE_IMAGE_ATOMIC = "1";
};
```

#### 3.2 GameMode Optimization

```nix
# OPTIMIZED GAMEMODE:
programs.gamemode = {
  enable = true;
  settings = {
    general = {
      desiredgov = "performance";
      inhibit_screensaver = true;
      require_display = true;
      use_systemd = true;
    };
    gpu = {
      # RTX 3090 specific optimizations
      nv_powermizer_mode = 1; # Maximum Performance
      nv_core_clock_mhz_offset = 200; # Higher overclock for RTX 3090
      nv_memory_transfer_rate_offset = 300; # Conservative memory overclock
      nv_gpu_utilization = "1";
      
      # DLSS optimizations
      nv_dlss = "1";
      nv_reflex = "1"; # NVIDIA Reflex for competitive gaming
    };
  };
};
```

#### 3.3 WiVRn Optimization

```nix
# OPTIMIZED WI VRN CONFIGURATION:
services.wivrn = {
  enable = true;
  openFirewall = true;
  defaultRuntime = true;
  config.enable = true;
  config.json = {
    device = {
      name = "Quest Pro";
      type = "quest_pro";
      resolution = "1800x1920";
      refresh_rate = 90;
    };
    
    stream = {
      codec = "hevc";
      targetBitrate = 200; # Increase from 150Mbps for RTX 3090
      spatial = true;
      temporal = true;
      
      nvidiaEncoder = {
        preset = "p7"; # Quality preset
        tune = "ll"; # Low latency tuning
        profile = "high";
        rc = "vbr";
        b = "200000"; # Increase from 150Mbps
        maxrate = "250000"; # Increase from 200Mbps
        bufsize = "400000"; # Increase from 300Mbps
        gop = "60";
        keyint = "60";
        refs = "4";
        bframes = "2";
        twoPass = "quarter_res";
        aq = "spatial";
        temporal_aq = "1";
        nonref_p = "1";
        strict_gop = "1";
      };
      encoder = "nvidia";
    };
    
    network = {
      protocol = "udp";
      localOptimization = true;
      frameTiming = {
        targetLatencyMs = 10; # Reduce from 12ms
        jitterBufferMs = 2; # Reduce from 3ms
      };
    };
    
    debug = {
      logLevel = "info";
      enableStats = true;
    };
  };
};
```

### 4. Mining Performance Optimization (Expected: 10-20% improvement)

#### 4.1 Thread and Resource Optimization

```nix
# OPTIMIZED MINING CONFIGURATION:
services.mining = {
  enable = true;
  user = "mining"; # Non-root user
  
  lolminer = {
    enable = true;
    algorithm = "CR29";
    pool = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
    wallet = "WALLET_PREFIX.NODE_NAME";
    nvidiaDevices = "0";
    powerLimit = 250; # RTX 3090 optimal
  };
  
  xmrig = {
    enable = true;
    pool = "stratum+ssl://xtm-rx-us.kryptex.network:8038";
    wallet = "WALLET_PREFIX.NODE_NAME";
    threads = 16; # Optimize for Ryzen 5950X
    httpToken = "mining_control";
  };
};

# OPTIMIZED SERVICE CONFIGURATIONS:
systemd.services = {
  lolminer-nvidia = mkIf cfg.lolminer.enable {
    description = "lolMiner NVIDIA Mining Service";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    
    serviceConfig = {
      User = "mining";
      Slice = "mining.slice";
      ExecStart = ''
        ${pkgs.steam-run}/bin/steam-run ${pkgs.lolminer}/bin/lolMiner \
          --algo ${cfg.lolminer.algorithm} \
          --pool ${cfg.lolminer.pool} \
          --user ${cfg.lolminer.wallet} \
          --devices ${cfg.lolminer.nvidiaDevices} \
          --pl ${toString cfg.lolminer.powerLimit} \
          --apiport 8080
      '';
      Restart = "always";
      RestartSec = "30s";
      Environment = ["LD_LIBRARY_PATH=/run/opengl-driver/lib"];
      
      # Performance optimizations
      CPUQuota = "90%";
      MemoryHigh = "80%";
      LimitMEMLOCK = "4G";
    };
  };
  
  xmrig = mkIf cfg.xmrig.enable {
    description = "XMRig CPU Mining Service";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    
    serviceConfig = {
      User = "mining";
      Slice = "mining.slice";
      LimitMEMLOCK = "4G";
      ExecStart = "${pkgs.xmrig}/bin/xmrig -o ${cfg.xmrig.pool} -u ${cfg.xmrig.wallet} -t 16 --http-port 8081 --http-access-token ${cfg.xmrig.httpToken} --http-no-restricted";
      Restart = "always";
    };
  };
};
```

#### 4.2 Smart Mining Management

```nix
# OPTIMIZED SMART MINING:
systemd.services.mining-smart-pause = {
  description = "Smart Mining Performance Control for VR/Gaming";
  wantedBy = ["multi-user.target"];
  wants = ["network-online.target"];
  after = ["network-online.target"];
  
  serviceConfig = {
    Type = "simple";
    ExecStart = "${pkgs.writeShellScript "mining-smart-pause" ''
      #!/bin/bash
      set -e
      
      # Configuration
      XMRIG_API_PORT=8081
      XMRIG_ACCESS_TOKEN=mining_control
      NORMAL_XMRIG_THREADS=16
      
      # Track previous state
      PREV_STATE="full"
      
      while true; do
        CURRENT_STATE="full"
        
        # Get current GPU utilization
        GPU_USAGE=$(/run/current-system/sw/bin/nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo "0")
        
        # Determine mining performance level
        if /run/current-system/sw/bin/pgrep -f "wivrn|steamvr|vrserver" > /dev/null 2>&1 && ! /run/current-system/sw/bin/pgrep -f "VRChat.*--no-vr" > /dev/null 2>&1; then
          CURRENT_STATE="minimal"
          echo "VR detected - minimal mining performance (2 CPU threads, RTX 3090 at optimal 250W power)"
          
        elif /run/current-system/sw/bin/pgrep -f "steam.*AppId|valheim|csgo|dota" > /dev/null 2>&1; then
          CURRENT_STATE="reduced"
          echo "Gaming detected - reduced mining performance (8 CPU threads, RTX 3090 at optimal 250W power)"
          
        elif [ "$GPU_USAGE" -gt 90 ] 2>/dev/null && ! /run/current-system/sw/bin/pgrep -f "VRChat.*--no-vr" > /dev/null 2>&1; then
          CURRENT_STATE="minimal"
          echo "Very high GPU usage ($GPU_USAGE%) - minimal mining performance"
          
        elif [ "$GPU_USAGE" -gt 70 ] 2>/dev/null && ! /run/current-system/sw/bin/pgrep -f "VRChat.*--no-vr" > /dev/null 2>&1; then
          CURRENT_STATE="reduced"
          echo "High GPU usage ($GPU_USAGE%) - reduced mining performance"
          
        else
          CURRENT_STATE="full"
          echo "Normal operation - full mining performance (16 CPU threads, RTX 3090 at optimal 250W power)"
        fi
        
        # Only make changes if state has changed
        if [ "$CURRENT_STATE" != "$PREV_STATE" ]; then
          case $CURRENT_STATE in
            "minimal")
              systemctl stop xmrig.service xmrig-reduced.service || true
              systemctl start xmrig-minimal.service || true
              ;;
            "reduced")
              systemctl stop xmrig.service xmrig-minimal.service || true
              systemctl start xmrig-reduced.service || true
              ;;
            "full")
              systemctl stop xmrig-reduced.service xmrig-minimal.service || true
              systemctl start xmrig.service || true
              ;;
          esac
          
          # RTX 3090 always runs at optimal 250W power
          systemctl start lolminer-nvidia.service || true
          PREV_STATE=$CURRENT_STATE
        fi
        
        sleep 5
      done
    ''}";
    Restart = "always";
    RestartSec = "10";
  };
};
```

## 📈 Performance Monitoring and Metrics

### 1. Build Performance Metrics

```nix
# ADD TO SYSTEM CONFIGURATION:
systemd.services.build-performance-monitor = {
  description = "Nix Build Performance Monitor";
  wantedBy = ["multi-user.target"];
  
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${pkgs.writeShellScript "build-performance" ''
      #!/bin/bash
      
      # Monitor build performance
      echo "=== NIX BUILD PERFORMANCE ===" >> /var/log/build-performance.log
      echo "Timestamp: $(date)" >> /var/log/build-performance.log
      echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)" >> /var/log/build-performance.log
      echo "Memory Usage: $(free -h | grep "Mem:" | awk '{print $3 "/" $2}')" >> /var/log/build-performance.log
      echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')" >> /var/log/build-performance.log
      echo "Nix Build Count: $(nix-store --query --references /nix/store | wc -l)" >> /var/log/build-performance.log
      echo "" >> /var/log/build-performance.log
    ''}";
  };
};
```

### 2. Gaming Performance Metrics

```nix
# ADD TO GAMING MODULE:
systemd.services.gaming-performance-monitor = {
  description = "Gaming Performance Monitor";
  wantedBy = ["multi-user.target"];
  
  serviceConfig = {
    Type = "simple";
    ExecStart = "${pkgs.writeShellScript "gaming-performance" ''
      #!/bin/bash
      
      while true; do
        echo "=== GAMING PERFORMANCE ===" >> /var/log/gaming-performance.log
        echo "Timestamp: $(date)" >> /var/log/gaming-performance.log
        echo "GPU Usage: $(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)" >> /var/log/gaming-performance.log
        echo "GPU Temp: $(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)" >> /var/log/gaming-performance.log
        echo "GPU Power: $(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits)" >> /var/log/gaming-performance.log
        echo "Memory Usage: $(free -h | grep "Mem:" | awk '{print $3 "/" $2}')" >> /var/log/gaming-performance.log
        echo "" >> /var/log/gaming-performance.log
        sleep 60
      done
    ''}";
  };
};
```

### 3. Mining Performance Metrics

```nix
# ADD TO MINING MODULE:
systemd.services.mining-performance-monitor = {
  description = "Mining Performance Monitor";
  wantedBy = ["multi-user.target"];
  
  serviceConfig = {
    Type = "simple";
    ExecStart = "${pkgs.writeShellScript "mining-performance" ''
      #!/bin/bash
      
      while true; do
        echo "=== MINING PERFORMANCE ===" >> /var/log/mining-performance.log
        echo "Timestamp: $(date)" >> /var/log/mining-performance.log
        
        # LolMiner stats
        if curl -s http://localhost:8080/api >/dev/null 2>&1; then
          echo "LolMiner Hashrate: $(curl -s http://localhost:8080/api | jq -r '.hashrate.total[0] // 0')" >> /var/log/mining-performance.log
        fi
        
        # XMRig stats
        if curl -s http://localhost:8081/json_rpc >/dev/null 2>&1; then
          echo "XMRig Hashrate: $(curl -s http://localhost:8081/json_rpc | jq -r '.result.hashrate.total[0] // 0')" >> /var/log/mining-performance.log
        fi
        
        echo "GPU Power: $(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits)" >> /var/log/mining-performance.log
        echo "GPU Temp: $(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)" >> /var/log/mining-performance.log
        echo "" >> /var/log/mining-performance.log
        sleep 60
      done
    ''}";
  };
};
```

## 🚀 Implementation Timeline

### Phase 1: Critical Performance (Week 1)
- [ ] Nix build optimization (max-jobs, cores)
- [ ] Basic resource management improvements
- [ ] Memory management optimization
- [ ] Test build performance improvements

### Phase 2: Gaming Performance (Week 2)
- [ ] NVIDIA driver optimization
- [ ] GameMode optimization
- [ ] WiVRn configuration optimization
- [ ] Test gaming performance improvements

### Phase 3: Mining Optimization (Week 3)
- [ ] Mining service optimization
- [ ] Thread allocation optimization
- [ ] Smart mining management
- [ ] Test mining performance improvements

### Phase 4: Monitoring and Tuning (Week 4)
- [ ] Performance monitoring setup
- [ ] Metrics collection and analysis
- [ ] Fine-tuning based on monitoring data
- [ ] Documentation and optimization guidelines

## 📊 Expected Performance Improvements

### Nix Build Performance
- **Target**: 40-60% faster builds
- **Current**: ~8 parallel jobs
- **Target**: 32 parallel jobs (full thread utilization)
- **Expected**: Build time reduction from 30 minutes to 12-18 minutes

### Gaming Performance
- **Target**: 15-25% performance improvement
- **Current**: Basic optimizations
- **Target**: Full NVIDIA optimization + GameMode
- **Expected**: Higher FPS, lower latency, better VR experience

### Mining Performance
- **Target**: 10-20% efficiency improvement
- **Current**: Basic mining setup
- **Target**: Optimized thread allocation + smart management
- **Expected**: Higher hashrate, better power efficiency

### System Performance
- **Target**: 20-30% resource utilization improvement
- **Current**: Suboptimal resource allocation
- **Target**: Balanced resource management
- **Expected**: Better multitasking, reduced system strain

## 🔧 Maintenance and Optimization

### Regular Performance Reviews
- **Weekly**: Monitor build performance metrics
- **Monthly**: Review gaming and mining performance
- **Quarterly**: Full system performance audit

### Performance Tuning Guidelines
- Monitor resource usage patterns
- Adjust limits based on actual usage
- Update configurations based on monitoring data
- Regular performance testing and benchmarking

### Optimization Best Practices
- Keep drivers updated
- Monitor system temperatures
- Regularly review resource allocation
- Test performance after major updates

This performance optimization plan will significantly improve system responsiveness, build times, and overall user experience while maintaining system stability and security.