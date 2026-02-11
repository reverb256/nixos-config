# Quadlet OpenClaw - Simple Autonomous Orchestration
# Corrected module following quadlet-nix documentation
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
  options.services.openclaw-quadlet = lib.mkEnableOption "OpenClaw quadlet orchestration";
  
  config = lib.mkIf cfg.enable {
    # Podman configuration
    virtualisation.podman = {
      enable = true;
      autoUpdate = true;
    };

    # OpenClaw on master node (zephyr)
    virtualisation.quadlet.containers.openclaw-master = {
      containerConfig = {
        Image = "ghcr.io/openclaw/openclaw-gateway:latest";
        Name = "openclaw-orchestrator";
        AutoStart = "yes";
        Restart = "always";
        
        # Workspace binding
        Bind = "${workspacePath}:/workspace";
        
        # Network (localhost only for security)
        PublishPort = ["127.0.0.1:18090"];
        
        # Security
        SecurityOpt = [
          "no-new-privileges=true"
          "label=disable"
        ];
        
        # Log driver
        LogDriver = "journald";
        
        # Resource limits (shared across all nodes)
        PidsLimit = 500;
        MemoryReservation = "2G";
        MemoryLimit = "8G";
        CpuQuota = "400";
      };
      
      serviceConfig = {
        Type = "service";
        After = ["network-online.target" "podman.service"];
        Wants = ["network-online.target"];
        Restart = "always";
        RestartSec = "10";
        OOMScoreAdjust = -500;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
      };
    };

    # Token authentication
    Environment = [
      "OPENCLAW_TOKEN=${cfg.authToken}"
      "OPENCLAW_AUTH_MODE=token"
      "OPENCLAW_AUTH_MODE=token"
      "OPENCLAW_GATEWAY_URL=http://100.81.182.5:${builtins.toString 18090}"
      ];
    };

    # Secure auth token storage (optional)
    systemd.tmpfiles.settings."openclaw-token".rules = lib.mkIf (cfg.authToken != "" && !config.age.secrets.enable) [
      "C /run/openclaw-token 0600 root root -"
    ];

    # Firewall configuration
    networking.firewall = lib.mkIf cfg.enable {
      # Only allow localhost access on master node
      allowedTCPPorts = [18090];
      
      interfaces."podman+".allowedTCPPorts = [];
      interfaces."podman+".allowedUDPPorts = [];
    };
  };
};
}
EOF
