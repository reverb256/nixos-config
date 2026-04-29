{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

  # Root filesystem is ephemeral BTRFS — only /persistent survives
  environment.persistence."/persistent" = {
    hideMounts = true;

    directories = [
      # System state
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/systemd/backlight"  # display brightness

      # Networking
      "/etc/NetworkManager/system-connections"
      "/var/lib/NetworkManager"

      # Bluetooth
      "/var/lib/bluetooth"

      # K3s / containerd — critical for cluster node
      "/var/lib/rancher"
      "/var/lib/cni"
      "/var/lib/kubelet"

      # Tailscale
      "/var/lib/tailscale"

      # agenix — decrypted secrets land in /run/agenix (tmpfs), but
      # the age plugin identity may write here
      "/var/lib/agenix"

      # fwupd firmware updates
      "/var/lib/fwupd"

      # Container storage is on bcache0 (/var/lib/containers in hardware.nix)
      # so it's NOT here — it's on a separate disk
    ];

    files = [
      # Machine identity
      "/etc/machine-id"

      # SSH host keys (persisted to avoid regenerating every boot)
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"

      # Nixos auto-generated uid/gid tracking
      "/var/lib/nixos/uid-map"
      "/var/lib/nixos/gid-map"
    ];

    # User-level persistence (j_kro)
    users.j_kro = {
      directories = [
        # SSH keys
        { directory = ".ssh"; mode = "0700"; }
        { directory = ".gnupg"; mode = "0700"; }

        # Hermes agent state
        ".hermes"
        ".cache"

        # Desktop / app state
        ".local"
        ".config"
        ".vscode"
        ".vscode-oss"

        # Development
        "workspace"

        # LM Studio models
        ".lmstudio"

        # direnv
        ".local/share/direnv"

        # NVIDIA compute cache
        ".nv"

        # HuggingFace cache
        ".cache/huggingface"

        # Keyrings
        { directory = ".local/share/keyrings"; mode = "0700"; }
      ];

      files = [
        ".screenrc"
      ];
    };
  };

  # Immutable users — required for impermanence
  # Passwords are set via initialHashedPassword (only applied if /etc/shadow
  # doesn't already exist in persistent storage)
  users.mutableUsers = false;
}
