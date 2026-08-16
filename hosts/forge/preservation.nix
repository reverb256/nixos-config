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
  # disable the commit-to-disk service. (Same pattern as nexus/sentry.)
  systemd.services.systemd-machine-id-commit.enable = false;

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

      # SOPS age key — secretspec-creds and secretspec-validator read
      # ageKeyFile = /etc/sops/age/key.txt (set in hosts/forge/configuration.nix).
      # The key is seeded ONCE by the operator at /persistent/etc/sops/age/key.txt;
      # this bindmount makes it durable across generations. It must NOT be
      # declared in configuration.nix (the 2026-08-16 audit found the previous
      # pkgs.writeText copy had leaked both private keys into git history).
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
      ];
      files = [
        ".screenrc"
      ];
    };
  };

  users.mutableUsers = false;
}
