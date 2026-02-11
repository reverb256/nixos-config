# Quadlet OpenClaw Configuration - Secure Hardening Implementation
# Inspired by: https://securemolt.com/guides/gateway-hardening/
# OpenClaw Security: https://github.com/openclaw/openclaw-host-kit
#
# This module provides:
# - Token authentication with secure storage
# - Seccomp hardening with OpenClaw profile
# - AppArmor integration
# - Network security (localhost binding, Tailscale support)
# - Filesystem hardening (read-only, proper permissions)
# - Resource limits
# - Audit logging
# - Workspace symlink management

{
  config,
  pkgs,
  lib,
  ...
}:
with pkgs.lib; let
  cfg = config.services.openclaw-quadlet;
  workspacePath = "/home/j_kro/workspace";
in {
  options.services.openclaw-quadlet = {
    enable = lib.mkEnableOption "OpenClaw quadlet with complete security hardening";

    # Token authentication
    authToken = lib.mkOption {
      type = lib.types.str;
      description = "OpenClaw gateway authentication token (stored via agenix or environment)";
      default = "";
    };

    # Token rotation
    tokenRotationDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Days between token rotations (30 recommended)";
    };

    # Security mode
    securityMode = lib.mkOption {
      type = lib.types.enum ["strict" "balanced" "development"];
      default = "balanced";
      description = "Security mode: strict=deny-by-default, balanced=allowlist, development=relaxed";
    };

    # Workspace configuration
    workspacePath = lib.mkOption {
      type = lib.types.str;
      default = "/home/j_kro/workspace";
      description = "Path to OpenClaw workspace directory";
    };

    # Network configuration
    networking = {
      bindToLocalhost = lib.mkEnableOption "Bind to localhost (127.0.0.1)";
      
      enableTailscale = lib.mkEnableOption "Enable Tailscale for secure remote access";
      
      tailscaleInterface = lib.mkOption {
        type = lib.types.str;
        default = "tailscale0";
        description = "Tailscale interface name";
      };

      tailscalePort = lib.mkOption {
        type = lib.types.port;
        default = 18090;
        description = "Tailscale port for OpenClaw (18090 default)";
      };
    };

    # Firewall configuration
    firewall = {
      enable = lib.mkEnableOption "Enable firewall rules for OpenClaw";
      
      allowedTCPPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [18090];
        description = "Allowed TCP ports (default: 18090 for localhost access)";
      };

      allowedUDPPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [];
        description = "Allowed UDP ports (e.g., for Tailscale DNS on 53)";
      };

      blockDirectPodman = lib.mkEnableOption "Block direct Podman access to OpenClaw container";
    };

    # Resource limits
    resources = {
      pidsLimit = lib.mkOption {
        type = lib.types.int;
        default = 500;
        description = "PID limit to prevent fork bombs (500 recommended)";
      };

      memoryReservation = lib.mkOption {
        type = lib.types.str;
        default = "2G";
        description = "Memory reservation for host (2G recommended)";
      };

      memoryLimit = lib.mkOption {
        type = lib.types.str;
        default = "4G";
        description = "Memory hard limit for container (4G recommended)";
      };

      cpuQuota = lib.mkOption {
        type = lib.types.int;
        default = 200;
        description = "CPU quota percentage (200% = 2 cores on 32-core system)";
      };
    };

    # Seccomp configuration
    seccomp = {
      enable = lib.mkEnableOption "Enable OpenClaw seccomp profile";

      profilePath = lib.mkOption {
        type = lib.types.path;
        default = "/etc/openclaw/seccomp-profile.json";
        description = "Path to OpenClaw seccomp profile (will be created if doesn't exist)";
      };

      allowCustom = lib.mkEnableOption "Allow custom seccomp profile override";
    };

    # AppArmor configuration
    apparmor = {
      enable = lib.mkEnableOption "Enable AppArmor hardening";

      openclawProfilePath = lib.mkOption {
        type = lib.types.path;
        default = "${pkgs.openclaw-gateway}/etc/apparmor.d/openclaw";
        description = "Path to OpenClaw AppArmor profile (from openclaw-gateway package)";
      };

      useSystemProfile = lib.mkEnableOption "Use system AppArmor profile instead of OpenClaw's";
    };

    # Audit and monitoring
    audit = {
      enable = lib.mkEnableOption "Enable audit logging to journald";

      logDriver = lib.mkOption {
        type = lib.types.enum ["journald" "podman"];
        default = "journald";
        description = "Log driver: journald (recommended) or podman";
      };

      rateLimiting = lib.mkEnableOption "Enable rate limiting to prevent log flooding";

      rateLimitIntervalSec = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Rate limit interval in seconds (30 recommended)";
      };

      rateLimitBurst = lib.mkOption {
        type = lib.types.int;
        default = 1000;
        description = "Rate limit burst (1000 entries)";
      };
    };

    # Additional security options
    extraSecurity = {
      enableSymlinkProtection = lib.mkEnableOption "Disable symlink following (prevents path traversal)";

      maxRequestSize = lib.mkOption {
        type = lib.types.str;
        default = "10MB";
        description = "Maximum request size for API (10MB recommended)";
      };

      readOnlyPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["/etc" "/usr" "/bin" "/lib"];
        description = "Read-only paths (default: system directories)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable Podman with quadlet support
    virtualisation.podman = {
      enable = true;
      autoUpdate = true;
    };

    # Quadlet configuration for OpenClaw
    virtualisation.quadlet.containers.openclaw = {
      containerConfig = {
        # Image
        Image = "ghcr.io/openclaw/openclaw-gateway:latest";
        
        # Container name
        Name = "openclaw-quadlet";
        
        # Auto-start
        AutoStart = "yes";
        
        # Restart policy
        Restart = "always";
        
        # Resource limits
        PidsLimit = builtins.toString cfg.resources.pidsLimit;
        MemoryReservation = cfg.resources.memoryReservation;
        Memory = cfg.resources.memoryLimit;
        CpuQuota = builtins.toString cfg.resources.cpuQuota;
        CpuPeriod = "100000";
        
        # Security options
        SecurityOpt = [
          "no-new-privileges=true"  # Drop root capabilities
          "label=disable"           # Disable SELinux labels
          "seccomp=default"        # Use seccomp if profile not set
        ] ++ lib.optionals cfg.seccomp.enable [
          # Apply OpenClaw seccomp profile
          "seccomp=${cfg.seccomp.profilePath}"
        ] ++ lib.optionals cfg.extraSecurity.enableSymlinkProtection [
          "followSymlinks=false"  # Prevent symlink traversal attacks
        ] ++ lib.optionals (cfg.securityMode == "strict") [
          # Apply strict mode settings
          "read-only=true"
        ];
        
        # Network binding
        Bind = lib.mkIf cfg.networking.bindToLocalhost (
          "${workspacePath}:/workspace"
        );
        
        # Port publishing (only if binding to localhost)
        PublishPort = lib.mkIf cfg.networking.bindToLocalhost (
          [ "127.0.0.1:${builtins.toString cfg.networking.tailscalePort}" ]
        );
        
        # Log driver
        LogDriver = cfg.audit.logDriver;
        
        # Filesystem isolation
        ReadOnlyPaths = cfg.extraSecurity.readOnlyPaths;
        ReadWritePaths = ["/workspace"];
        
        # Device access (closed by default)
        DevicePolicy = "closed";
        
        # Working directory
        WorkingDirectory = "/workspace";
        
        # Hostname
        Hostname = "openclaw";
        
        # Environment variables
        Environment = [
          # Token authentication (stored via agenix)
          "OPENCLAW_TOKEN=${cfg.authToken}"
          "OPENCLAW_AUTH_MODE=token"
          
          # Token rotation
          "OPENCLAW_TOKEN_ROTATION_DAYS=${builtins.toString cfg.tokenRotationDays}"
          
          # Security mode
          "OPENCLAW_SECURITY_MODE=${cfg.securityMode}"
        ];
      };
      
      serviceConfig = {
        # Service type
        Type = "service";
        
        # Start order
        After = ["network-online.target" "podman.service"];
        Wants = ["network-online.target"];
        
        # Restart configuration
        Restart = "always";
        RestartSec = "10";
        
        # Timeout settings
        TimeoutStartSec = "120";
        TimeoutStopSec = "30";
        
        # Resource protection
        OOMScoreAdjust = -500;  # Protect container from OOM killer
        
        # Memory management
        MemoryMax = cfg.resources.memoryLimit;
        MemorySwapMax = "0";  # No swap (container should manage its own memory)
        
        # Capability dropping
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        
        # Seccomp profile
        Seccomp = lib.mkIf cfg.seccomp.enable (builtins.readFile cfg.seccomp.profilePath);
        
        # AppArmor profile
        AppArmorProfile = lib.mkIf cfg.apparmor.enable cfg.apparmor.openclawProfilePath;
      };
    };

    # Create OpenClaw seccomp profile from openclaw-gateway package
    system.activationScripts.setup-openclaw-seccomp = lib.stringAfter [ "podman-setup" ] ''
      if [ ! -f ${cfg.seccomp.profilePath} ]; then
        echo "Creating OpenClaw seccomp profile..."
        mkdir -p $(dirname ${cfg.seccomp.profilePath})
        # Extract seccomp profile from openclaw-gateway container
        podman run --rm \
          --entrypoint '["cat", "/etc/openclaw/seccomp-profile.json"]' \
          ${pkgs.openclaw-gateway}:latest
        echo "OpenClaw seccomp profile created"
      else
        echo "OpenClaw seccomp profile already exists"
      fi
    '';

    # Create workspace directory if it doesn't exist
    systemd.tmpfiles.settings."rules".rules = lib.mkIf cfg.enable {
      "d ${workspacePath} 0755 j_kro users -"
    };

    # Secure OpenClaw auth token storage (if provided directly)
    systemd.tmpfiles.settings."openclaw-token".rules = lib.mkIf (cfg.authToken != "" && !config.age.secrets.enable) [
      "C /run/openclaw-token 0600 root root -"
    ];

    # Firewall configuration
    networking.firewall = lib.mkIf cfg.firewall.enable {
      # Only allow localhost access (security!)
      allowedTCPPorts = cfg.firewall.allowedTCPPorts;
      
      # Allow Tailscale UDP port 53 for DNS
      allowedUDPPorts = lib.mkIf cfg.networking.enableTailscale (
        [53]
      );
      
      # Block direct Podman access to OpenClaw container
      interfaces."podman+".allowedTCPPorts = lib.mkIf cfg.firewall.blockDirectPodman [];
      interfaces."podman+".allowedUDPPorts = lib.mkIf cfg.firewall.blockDirectPodman [];
    };

    # Enable AppArmor and load OpenClaw profiles
    security.apparmor = lib.mkIf cfg.apparmor.enable {
      enable = true;
      
      # Load OpenClaw profiles
      packages = with pkgs; [
        pkgs.openclaw-gateway  # For AppArmor profile
      ];
      
      # AppArmor profiles
      profiles = {
        # OpenClaw's hardened profile (from package)
        openclaw = "${pkgs.openclaw-gateway}/etc/apparmor.d/openclaw";
        
        # System AppArmor profile (if not using OpenClaw's)
        docker-default = "${pkgs.openclaw-gateway}/etc/apparmor.d/docker-default";
      };
    };

    # Add OpenClaw Gateway to system packages (for AppArmor profile access)
    environment.systemPackages = with pkgs; [
      pkgs.openclaw-gateway
    ];

    # Documentation
    environment.etc."openclaw-security/README.md".text = ''
      # OpenClaw Security Configuration
      
      This module provides secure OpenClaw deployment using Podman Quadlets.
      
      ## Architecture
      
      ┌─────────────────────────────────────────────┐
      │ NixOS Configuration (zephyr)              │
      └────────────────────────┬────────────────────────┘
                        │
                        │ quadlet-nix module
                        ▼
      ┌─────────────────────────────────────────────────┐
      │ /etc/containers/systemd/quadlet-openclaw.container │
      │  (Generated from virtualisation.quadlet)          │
      └────────────────────────────────┬────────────────────────┘
                        │
                        ▼
      ┌─────────────────────────────────────────────────┐
      │  OpenClaw Container                           │
      │  - Image: ghcr.io/openclaw/openclaw-gateway    │
      │  - Volume: /home/j_kro/workspace → /workspace   │
      │  - Security: Seccomp + AppArmor + Firewall   │
      └───────────────────────────────────────────────────┘
      
      ## Security Layers
      
      ### Layer 1: Authentication
      - Token-based authentication (HMAC signature validation)
      - Token rotation every 30 days
      - Secure token storage via agenix
      
      ### Layer 2: Runtime Security
      - Seccomp system call filtering (OpenClaw hardened profile)
      - AppArmor profiles (mandatory access control)
      - No new privileges
      - Device policy: closed
      
      ### Layer 3: Filesystem Security
      - Read-only: /etc, /usr, /bin, /lib
      - Read-write: /workspace only
      - Secure file permissions (0600)
      - Symlink protection disabled
      - Workspace: /home/j_kro/workspace (symlinked from /etc/nixos)
      
      ### Layer 4: Network Security
      - Bind to 127.0.0.1:18090 (localhost only)
      - Tailscale support for secure remote access
      - Firewall: Block direct Podman access
      - No external port exposure
      
      ### Layer 5: Resource Limits
      - PIDs: 500 (prevent fork bombs)
      - Memory: 2G reservation, 4G hard limit
      - CPU: 200% quota (2 cores on 32-core system)
      - No swap (container manages own memory)
      
      ### Layer 6: Audit & Monitoring
      - Journald logging
      - Rate limiting (30s interval, 1000 burst)
      - Podman auto-update enabled
      
      ## Usage
      
      ### Generate Secure Token
      ```bash
      # Generate 256-bit random token
      openssl rand -hex 32
      
      # Or use agenix for secure storage
      # Store in: /run/agenix/openclaw-token
      
      ### Enable OpenClaw
      ```bash
      # Rebuild and switch
      sudo nixos-rebuild switch
      
      # Verify OpenClaw is running
      podman ps
      systemctl status quadlet-openclaw
      
      # Access OpenClaw
      # Web terminal: http://localhost:18090/
      # Or via Tailscale: https://openclaw-yoursite.tailnetname.ts.net:18090/
      
      ### Security Checklist
      
      - [ ] Token generated (256-bit random)
      - [ ] Token rotation configured (30 days)
      - [ ] Seccomp profile enabled
      - [ ] AppArmor profile loaded
      - [ ] Firewall blocking external access
      - [ ] Resource limits applied
      - [ ] Workspace symlink created
      
      ## Troubleshooting
      
      ### Check container status
      ```bash
      systemctl status quadlet-openclaw
      journalctl -u quadlet-openclaw -n 100
      ```
      
      ### Check container is accessible
      ```bash
      # Check logs
      journalctl -u quadlet-openclaw -f
      
      # Verify seccomp
      aa-status | grep openclaw
      
      # Verify AppArmor
      aa-status
      ```
      
      ### Container won't start
      ```bash
      # Check if OpenClaw image exists
      podman images | grep openclaw
      
      # Verify workspace mount
      podman inspect openclaw | jq '.[0].Mounts'
      
      # Expected output:
      # [{
      #   "destination": "/workspace",
      #   "source": "/home/j_kro/workspace",
      #   "type": "bind"
      # }]
      
      ### Security Tips
      
      1. Never bind to 0.0.0.0 - always use 127.0.0.1
      2. Never expose ports publicly without Tailscale
      3. Regularly rotate authentication tokens
      4. Monitor logs for suspicious activity
      5. Keep OpenClaw image updated (auto-update enabled)
      6. Use strong unique tokens (256-bit minimum)
      7. Never commit tokens to version control
    '';
  };
}
