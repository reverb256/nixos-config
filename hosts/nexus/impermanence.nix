{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
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
      "/var/lib/systemd/backlight" # display brightness

      # Networking
      "/etc/NetworkManager/system-connections"
      "/var/lib/NetworkManager"

      # SSH host keys - persist entire directory to avoid file conflicts
      "/etc/ssh"

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

    # User-level persistence (j_kro)
    users.j_kro = {
      directories = [
        # SSH keys
        {
          directory = ".ssh";
          mode = "0700";
        }
        {
          directory = ".gnupg";
          mode = "0700";
        }

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

  # machine-id and age key: symlink to persistent storage instead of
  # bind mounts. NixOS activation creates these files before impermanence
  # bind mount services run, causing "A file already exists" failures.
  # Symlinks are created AFTER activation, overriding what NixOS made.
  # Seed uid-map/gid-map with valid JSON on fresh impermanence installs
  system.activationScripts.seed-uid-gid-maps = lib.stringAfter ["etc"] ''
    for f in /var/lib/nixos/uid-map /var/lib/nixos/gid-map /persistent/var/lib/nixos/uid-map /persistent/var/lib/nixos/gid-map; do
      if [ -f "$f" ] && [ ! -s "$f" ]; then
        echo '{}' > "$f"
      fi
    done
  '';

  system.activationScripts.persist-symlinks = lib.stringAfter ["etc" "users"] ''
    # machine-id: remove NixOS symlink and point to persistent copy
    if [ -f /persistent/etc/machine-id ]; then
      rm -f /etc/machine-id
      ln -sf /persistent/etc/machine-id /etc/machine-id
    fi
    # age key: remove activation-created file and symlink to persistent
    if [ -f /persistent/etc/age/key.txt ]; then
      rm -f /etc/age/key.txt
      ln -sf /persistent/etc/age/key.txt /etc/age/key.txt
    fi
  '';

  # Immutable users — required for impermanence
  # Passwords are set via initialHashedPassword (only applied if /etc/shadow
  # doesn't already exist in persistent storage)
  users.mutableUsers = false;

  # Fix stacked btrfs bind mounts on uid-map/gid-map.
  # The impermanence module creates file-level bind mounts that stack on each
  # failed nixos-rebuild switch, causing update-users-groups.pl rename() EBUSY.
  system.activationScripts.fix-nixos-mount-stacking = lib.stringAfter ["specialfs"] ''
    for f in /var/lib/nixos/uid-map /var/lib/nixos/gid-map; do
      while mountpoint -q "$f" 2>/dev/null; do
        umount -l "$f" 2>/dev/null || break
      done
    done
  '';
}
