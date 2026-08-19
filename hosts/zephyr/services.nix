{ config, pkgs, ... }:

let
  # Import the cloudflared module
  cloudflared = import ./modules/services/cloudflared.nix;
in
{
  # Haven server - runs directly on the host, not in K8s
  # This keeps 127.0.0.1:3000 accessible for cloudflared
  services.haven = {
    enable = false; # Disable - we run it manually via systemd
    
    # We'll run Haven as a systemd service directly
    # using the installer script approach
  };
  
  # Cloudflare Tunnel configuration
  cloudflared.enable = true;
  cloudflared.tunnelId = "my-haven-tunnel";
  cloudflared.credentialsFile = "/run/secrets/cloudflared-token";
  
  # Ingress rule: map haven.reverb256.ca to localhost:3000
  cloudflared.ingressRules = [
    {
      hostname = "haven.reverb256.ca";
      service = "http://127.0.0.1:3000";
    }
  ];
  
  # QUIC for faster connections
  cloudflared.quicEnabled = true;
  
  # Cloudflare Tunnel metrics port
  cloudflared.metricsPort = 54162;
  
  # Firewall allowed port for metrics
  networking.firewall.allowedTCPPorts = [ 54162 ];
}
