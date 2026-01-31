# OpenClaw AI Assistant Module
# Deploys OpenClaw to NixOS nodes via npm (nix-openclaw flake is broken)

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.openclaw;
in
{
  options.programs.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI assistant";
    
    nodeName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Name of this node in the OpenClaw cluster";
    };
    
    gatewayPort = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "Port for OpenClaw gateway";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install OpenClaw CLI tools via npm wrappers
    home-manager.users.j_kro = { config, pkgs, ... }: {
      home.packages = [
        # OpenClaw CLI
        (pkgs.writeShellScriptBin "openclaw" ''
          exec ${pkgs.nodejs_22}/bin/npx openclaw "$@"
        '')
        
        # ClawdHub CLI
        (pkgs.writeShellScriptBin "clawdhub" ''
          exec ${pkgs.nodejs_22}/bin/npx clawdhub "$@"
        '')
        
        # Bird (Twitter/X CLI)
        (pkgs.writeShellScriptBin "bird" ''
          exec ${pkgs.nodejs_22}/bin/npx @steipete/bird "$@"
        '')
        
        # Summarize (content summarizer)
        (pkgs.writeShellScriptBin "summarize" ''
          exec ${pkgs.nodejs_22}/bin/npx @steipete/summarize "$@"
        '')
        
        # Camsnap (RTSP camera)
        (pkgs.writeShellScriptBin "camsnap" ''
          exec ${pkgs.nodejs_22}/bin/npx @steipete/camsnap "$@"
        '')
      ];
      
      # Ensure npm packages can be installed
      home.file".npmrc".text = ''
        prefix=~/.npm-packages
      '';
    };

    # Install dependencies
    environment.systemPackages = with pkgs; [
      nodejs_22
      go
      bun
      git
      curl
      jq
      _1password-cli
      himalaya
      spotify-player
    ];

    # Open firewall for OpenClaw gateway (optional - only if needed externally)
    # networking.firewall.allowedTCPPorts = [ cfg.gatewayPort ];
  };
}
