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
    # System state
    directories = [
      "/etc/ssh"
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/systemd/backlight"
      "/etc/NetworkManager/system-connections"
      "/var/lib/NetworkManager"
      "/var/lib/bluetooth"
      "/var/lib/rancher"
      "/var/lib/cni"
      "/var/lib/kubelet"
      "/var/lib/tailscale"
      "/var/lib/fwupd"
      "/etc/nixos/.age"
      "/etc/ssl/cluster-ca"
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
        ".hermes"
        ".cache"
        ".local"
        ".config"
        ".vscode"
        ".vscode-oss"
        "workspace"
        ".lmstudio"
        ".local/share/direnv"
        ".nv"
        ".cache/huggingface"
        {
          directory = ".local/share/keyrings";
          mode = "0700";
        }
      ];
      files = [
        ".screenrc"
      ];
    };
  };

  users.mutableUsers = false;
}
