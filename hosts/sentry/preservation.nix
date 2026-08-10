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

  # preservation persists /etc/machine-id on a persistent filesystem (bind-mounted
  # from /persistent), so it is NOT on a transient tmpfs. systemd-machine-id-commit
  # expects machine-id on a tmpfs and errors ("not on a temporary file system"),
  # which fails activation. The machine-id is already durable via preservation, so
  # disable the commit-to-disk service.
  systemd.services.systemd-machine-id-commit.enable = false;

  preservation.preserveAt."/persistent" = {
    # System state — survives generation rollback
    directories = [
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
      # SSH host keys: persist individually as symlinks. Do NOT add "/etc/ssh"
      # to `directories` — bind-mounting /persistent/etc/ssh over /etc/ssh
      # shadows the store-generated sshd_config/ssh_config/ssh_known_hosts and
      # kills sshd ("/etc/ssh/sshd_config: No such file or directory", exit 1,
      # start-limit-hit). #2026-08-09 incident. Only the keys need persistence.
      {
        file = "/etc/ssh/ssh_host_ed25519_key";
        how = "symlink";
        mode = "0600";
      }
      {
        file = "/etc/ssh/ssh_host_ed25519_key.pub";
        how = "symlink";
        mode = "0644";
      }
      {
        file = "/etc/ssh/ssh_host_rsa_key";
        how = "symlink";
        mode = "0600";
      }
      {
        file = "/etc/ssh/ssh_host_rsa_key.pub";
        how = "symlink";
        mode = "0644";
      }
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
