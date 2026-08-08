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
