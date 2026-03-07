# Example configuration for Nextcloud module
# Add this to your /etc/nixos/configuration.nix

{ config, pkgs, ... }: {
  # ============================================================================
  # NEXTCLOUD CONFIGURATION
  # ============================================================================
  services.nextcloud-module = {
    enable = true;

    # Basic setup
    hostName = "cloud.zephyr.local";  # Change to your hostname

    # Database (automatically created)
    database = {
      create = true;
      name = "nextcloud";
      user = "nextcloud";
    };

    # Admin account (use Agenix for secrets!)
    admin = {
      user = "j_kro";  # Or "admin"
      passwordFile = "/run/agenix/nextcloud-admin-pass";
    };

    # Storage
    dataDir = "/var/lib/nextcloud";
    maxUploadSize = "16G";  # For large LLM model files, logs, etc.

    # Apps - enable what you need
    apps = {
      enable = true;

      # Core file sync
      files = true;      # File sync and sharing

      # Collaboration
      text = true;       # Collaborative Markdown
      deck = true;       # Kanban boards (great for agent workflows!)
      calendar = true;   # CalDAV calendar
      contacts = true;   # CardDAV contacts
      tasks = true;      # Task management
      notes = true;      # Quick Markdown notes

      # Communication
      talk = true;       # Video calls, chat, Matrix bridge

      # Office suites (pick one)
      onlyoffice = false;
      collabora = false;
    };

    # HTTPS
    https = true;

    # Synapse integration
    synapseIntegration = {
      enable = true;  # Creates directories for AI agent data
      dataDir = "/var/lib/nextcloud/data/synapse";
    };

    # PHP tuning
    php = {
      memoryLimit = "512M";
      maxExecutionTime = 3600;  # For large file uploads
    };
  };

  # ============================================================================
  # AGENIX SECRET (for admin password)
  # ============================================================================
  # Create a secret file with:
  # printf "your-secure-password" | agenix -e nextcloud-admin-pass
  #
  # Then add to your secrets.nix:
  # "nextcloud-admin-pass".file = ./secrets/nextcloud-admin-pass.age;
}
