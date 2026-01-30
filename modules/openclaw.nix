{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.openclaw;
in
{
  options.programs.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI assistant";
    
    documents = lib.mkOption {
      type = lib.types.path;
      default = ./../home/openclaw-docs;
      description = "Path to OpenClaw documents directory (AGENTS.md, SOUL.md, TOOLS.md)";
    };
    
    telegramTokenFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/agenix/openclaw-telegram-token";
      description = "Path to Telegram bot token file (Agenix encrypted)";
    };
    
    model = lib.mkOption {
      type = lib.types.str;
      default = "llama3.2:3b";
      description = "Default Ollama model to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Import the nix-openclaw Home Manager module
    home-manager.users.j_kro = { config, ... }: {
      imports = [ inputs.nix-openclaw.homeManagerModules.openclaw ];
      
      programs.openclaw = {
        enable = true;
        
        # Documents directory
        documents = cfg.documents;
        
        # Enable ALL first-party plugins on ALL hosts
        firstParty = {
          summarize.enable = true;
          peekaboo.enable = true;
          oracle.enable = true;
          poltergeist.enable = true;
          sag.enable = true;
          camsnap.enable = true;
          gogcli.enable = true;
          bird.enable = true;
          sonoscli.enable = true;
          imsg.enable = true;
        };
        
        # New API: Use 'config' instead of 'defaults' and 'providers'
        config = {
          # Configure Telegram provider - DISABLED (no token configured yet)
          channels.telegram = {
            enable = false;
            # tokenFile = cfg.telegramTokenFile;
            # allowFrom = [ 12345678 ]; # your Telegram user ID
          };
          
          # Model configuration
          model = "ollama/${cfg.model}";
        };
        
        # Systemd user service - ENABLED (testing if bug is fixed in new version)
        systemd.enable = true;
      };
    };
    
    # Ensure required packages are available
    environment.systemPackages = with pkgs; [
      jq
      curl
    ];
  };
}
