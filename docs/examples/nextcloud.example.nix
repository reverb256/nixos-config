# Example configuration for Nextcloud module
# Add this to your /etc/nixos/configuration.nix
{...}: {
  # ============================================================================
  # NEXTCLOUD CONFIGURATION
  # ============================================================================
  services.nextcloud-module = {
    enable = true;

    # Basic setup
    hostName = "cloud.zephyr.local"; # Change to your hostname

    # Database (automatically created)
    database = {
      create = true;
      name = "nextcloud";
      user = "nextcloud";
    };

    # Admin account (password managed by Agenix)
    admin = {
      user = "j_kro"; # Or "admin"
      passwordFile = "/run/agenix/nextcloud-admin";
    };

    # Storage
    dataDir = "/var/lib/nextcloud";
    maxUploadSize = "16G"; # For large LLM model files, logs, etc.

    # Apps - enable what you need
    apps = {
      enable = true;

      # Core file sync
      files = true; # File sync and sharing

      # Collaboration
      text = true; # Collaborative Markdown
      deck = true; # Kanban boards (great for agent workflows!)
      calendar = true; # CalDAV calendar
      contacts = true; # CardDAV contacts
      tasks = true; # Task management
      notes = true; # Quick Markdown notes

      # Communication
      talk = true; # Video calls, chat, Matrix bridge

      # Office suites (pick one)
      onlyoffice = false;
      collabora = false;
    };

    # HTTPS
    https = true;

    # PHP tuning
    php = {
      memoryLimit = "512M";
      maxExecutionTime = 3600; # For large file uploads
    };
  };

  # ============================================================================
  # AGENIX SECRET (for admin password)
  # ============================================================================
  # The password is encrypted in:
  #   /data/@projects/infra/nixos/secrets/nextcloud-admin.age
  #
  # Decrypted at runtime to: /run/agenix/nextcloud-admin
  #
  # To view the password:
  #   age --decrypt /data/@projects/infra/nixos/secrets/nextcloud-admin.age
  #
  # To regenerate:
  #   tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 32 | \
  #     age -R /path/to/recipients.txt > nextcloud-admin.age
}
