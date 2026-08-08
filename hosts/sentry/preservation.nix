{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.preservation.nixosModules.preservation
  ];

  preservation.enable = true;

  preservation.preserveAt."/persistent" = {
    # System state — survives generation rollback
    directories = [
      "/etc/ssh"
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/systemd/backlight"
      "/etc/NetworkManager/system-connections"
      "/var/lib/NetworkManager"
      "/var/lib/bluetooth"
      "/var/lib/tailscale"
      "/var/lib/fwupd"

      # SOPS age key — sops-nix reads sops.age.keyFile = /etc/nixos/.age/key.txt
      # (set in modules/system/sops-secrets-registry.nix). This path is NOT
      # covered by the /etc/age/key.txt symlink below, so persist it explicitly.
      "/etc/nixos/.age"
      "/etc/sops/age"
    ];
    files = [
      {
        file = "/etc/machine-id";
        inInitrd = true;
      }
    ];

    users.j_kro = {
      directories = [
        {
          directory = ".ssh";
          mode = "0700";
        }
        {
          directory = ".gnupg";
          mode = "0700";
        }
        ".local/share/keyrings"
        ".cache/huggingface"
        ".local/share/direnv"
        ".config" # Declarative user config
        ".local/share" # User app state
        ".agents" # Agent state and configs
        # tplink-backups not tracked - empty dir, likely migrated elsewhere
      ];
      files = [
        ".screenrc"
        ".gtkrc-2.0.backup"
      ];
    };

    # CRITICAL: Crypto wallet preservation (Zen Browser)
    # Already backed up to Nexus - will restore after disko install
    # Backup: /data/backups/sentry-20260531/zen-browser-profile.tar.gz (1.3 GB)
  };

  users.mutableUsers = false;
}
