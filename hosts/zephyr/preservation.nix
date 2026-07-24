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

  # machine-id and age key: symlink to persistent storage
  system.activationScripts.persist-symlinks = lib.stringAfter ["etc" "users"] ''
    if [ -f /persistent/etc/machine-id ]; then
      rm -f /etc/machine-id
      ln -sf /persistent/etc/machine-id /etc/machine-id
    fi
    if [ -f /persistent/etc/age/key.txt ]; then
      rm -f /etc/age/key.txt
      ln -sf /persistent/etc/age/key.txt /etc/age/key.txt
    fi
  '';

  users.mutableUsers = false;
}
