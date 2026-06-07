# Unified USB — Portable NixOS + Rescue Operations
#
# Boots on any x86_64 machine. Provides:
#   - Full Niri desktop for daily work (niri, fish, starship, git, vim, tmux)
#   - Rescue tools (btrfs-progs, lvm2, cryptsetup, mdadm, smartmontools)
#   - Rescue scripts (detect-hosts, mount-cluster, rebuild-host, hardware-scan, boot-diagnostics, fix-btrfs-default)
#   - Hermes agent pointing at AI gateway
#   - SSH access via j_kro user
#   - Network access (NetworkManager, DHCP)
#   - NFS client for mounting config from Zephyr
#
# Build:  nix build .#nixosConfigurations.usb.config.system.build.isoImage
# Flash:  sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress
#
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvekxGk1YR/eF8llVmNk3C59BtgB+9DNvxLy2WjPEyb j_kro@zephyr";

  # Rescue scripts from /etc/nixos/scripts/rescue/
  rescue-scripts =
    pkgs.runCommand "rescue-scripts" {
      buildInputs = [pkgs.bash];
    } ''
      mkdir -p $out/bin $out/share/doc
      cp ${../../scripts/rescue/detect-hosts.sh} $out/bin/rescue-detect-hosts
      cp ${../../scripts/rescue/mount-cluster.sh} $out/bin/rescue-mount-cluster
      cp ${../../scripts/rescue/rebuild-host.sh} $out/bin/rescue-rebuild-host
      cp ${../../scripts/rescue/hardware-scan.sh} $out/bin/rescue-hardware-scan
      cp ${../../scripts/rescue/boot-diagnostics.sh} $out/bin/rescue-boot-diagnostics
      cp ${../../scripts/rescue/fix-btrfs-default.sh} $out/bin/rescue-fix-btrfs-default
      chmod +x $out/bin/rescue-*
      cp ${../../scripts/rescue/RESCUE-GUIDE.md} $out/share/doc/RESCUE-GUIDE.md
      cp ${../../scripts/rescue/RESCUE-AGENT.md} $out/share/doc/RESCUE-AGENT.md
    '';

  rescue-script = pkgs.writeShellScriptBin "rescue" ''
    #!/usr/bin/env bash
    set -euo pipefail

    RED='\033[0;31m'
    GRN='\033[0;32m'
    YEL='\033[1;33m'
    BLU='\033[0;34m'
    NC='\033[0m'

    while true; do
      clear
      echo -e "''${BLU}╔═══════════════════════════════════════════════════════════╗''${NC}"
      echo -e "''${BLU}║      Unified NixOS USB — Workstation + Rescue v2.0        ║''${NC}"
      echo -e "''${BLU}╠═══════════════════════════════════════════════════════════╣''${NC}"
      echo -e "''${BLU}║ 1) Detect cluster hosts (network scan)                   ║''${NC}"
      echo -e "''${BLU}║ 2) Mount NFS share from Zephyr                           ║''${NC}"
      echo -e "''${BLU}║ 3) Scan local hardware and disks                         ║''${NC}"
      echo -e "''${BLU}║ 4) Run boot diagnostics                                  ║''${NC}"
      echo -e "''${BLU}║ 5) Rebuild a host from NFS config                        ║''${NC}"
      echo -e "''${BLU}║ 6) Fix btrfs default subvolume                           ║''${NC}"
      echo -e "''${BLU}║ 7) Manual mount/chroot                                   ║''${NC}"
      echo -e "''${BLU}║ 8) SSH into cluster host                                 ║''${NC}"
      echo -e "''${BLU}║ 9) Launch Hermes AI assistant                            ║''${NC}"
      echo -e "''${BLU}║ 0) Reboot                                                ║''${NC}"
      echo -e "''${BLU}╚═══════════════════════════════════════════════════════════╝''${NC}"
      echo ""
      echo -n "Select [0-9]: "
      read -r choice

      case $choice in
        1)
          clear
          echo -e "''${YEL}==> Scanning cluster network''${NC}"
          echo ""
          rescue-detect-hosts || echo "Script not found"
          echo ""
          read -p "Press Enter to continue..."
          ;;
        2)
          clear
          echo -e "''${YEL}==> Mounting cluster resources''${NC}"
          echo ""
          rescue-mount-cluster || echo "Script not found"
          echo ""
          read -p "Press Enter to continue..."
          ;;
        3)
          clear
          echo -e "''${YEL}==> Hardware scan''${NC}"
          echo ""
          rescue-hardware-scan || echo "Script not found"
          echo ""
          read -p "Press Enter to continue..."
          ;;
        4)
          clear
          echo -e "''${YEL}==> Boot diagnostics''${NC}"
          echo ""
          rescue-boot-diagnostics || echo "Script not found"
          echo ""
          read -p "Press Enter to continue..."
          ;;
        5)
          clear
          echo -e "''${YEL}==> Rebuild host from NFS''${NC}"
          echo ""
          echo "Usage: rescue-rebuild-host <hostname> [path-to-config]"
          echo ""
          read -p "Press Enter to continue..."
          ;;
        6)
          clear
          echo -e "''${YEL}==> Fix btrfs default subvolume''${NC}"
          echo ""
          echo "Usage: rescue-fix-btrfs-default <device> <subvolume>"
          echo ""
          read -p "Press Enter to continue..."
          ;;
        7)
          clear
          echo -e "''${YEL}==> Manual mount/chroot''${NC}"
          echo ""
          echo "Steps:"
          echo "1. Identify target disk: lsblk -f"
          echo "2. Mount root: mount /dev/sdX2 /mnt"
          echo "3. Mount boot: mount /dev/sdX1 /mnt/boot"
          echo "4. Enter chroot: nixos-enter /mnt"
          echo ""
          read -p "Press Enter to continue..."
          ;;
        8)
          clear
          echo -e "''${YEL}==> SSH to cluster host''${NC}"
          echo ""
          echo "Available hosts:"
          echo "  zephyr (10.1.1.110)"
          echo "  nexus (10.1.1.120)"
          echo "  forge (10.1.1.130)"
          echo "  sentry (10.1.1.140)"
          echo ""
          read -p "Enter hostname: " host
          ssh "j_kro@$host" || true
          ;;
        9)
          clear
          echo -e "''${YEL}==> Launch Hermes AI assistant''${NC}"
          echo ""
          echo "Run: hermes"
          echo ""
          read -p "Press Enter to continue..."
          ;;
        0)
          clear
          echo -e "''${YEL}==> Rebooting''${NC}"
          echo ""
          sudo reboot || poweroff
          ;;
        *)
          echo -e "''${RED}Invalid option''${NC}"
          sleep 2
          ;;
      esac
    done
  '';
in {
  imports = [
    # ISO image base
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-calamares.nix"

    ./hardware-usb.nix

    # Selective module imports (NOT modules/default.nix — too heavy)
    ../../modules/system/nix-config.nix
    ../../modules/system/fetch-tools.nix
    ../../modules/shell/fish.nix
    ../../modules/desktop/niri.nix
    ../../modules/desktop/wayland-common.nix
    ../../modules/desktop/wayland-compositor-common.nix
    ../../modules/desktop/desktop.nix
    ../../modules/desktop/stylix.nix
    ../../modules/network-constants.nix

    # Flake inputs
    inputs.niri.nixosModules.niri
    inputs.home-manager.nixosModules.home-manager
    inputs.stylix.nixosModules.stylix
    inputs.agenix.nixosModules.age
  ];

  # ISO Settings
  isoImage.makeUsbBootable = true;
  isoImage.makeEfiBootable = true;

  # Boot
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.timeout = lib.mkForce 5;
  boot.plymouth.enable = lib.mkForce false;
  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;
  boot.supportedFilesystems = lib.mkForce ["ext4" "btrfs" "vfat" "xfs" "ntfs"];
  boot.kernelParams = [
    "copytoram"
    "amd_iommu=on"
    "iommu=pt"
  ];
  boot.blacklistedKernelModules = [
    "snd_seq_dummy"
    "snd_hrtimer"
    "ufs"
    "hfs"
    "hfsplus"
    "reiserfs"
    "appletalk"
    "ipx"
    "decnet"
  ];

  # Networking
  networking = {
    hostName = "usb";
    networkmanager.enable = true;
    wireless.enable = true;
    useDHCP = lib.mkDefault true;
    extraHosts = ''
      10.1.1.110  zephyr
      10.1.1.120  nexus
      10.1.1.130  forge
      10.1.1.140  sentry
      10.1.1.100  k8s-vip
    '';
    firewall.allowedTCPPorts = lib.mkOptionDefault [22];
  };

  # Timezone
  i18n.defaultLocale = "en_CA.UTF-8";
  time.timeZone = "America/Winnipeg";

  # GPU / Graphics — no specific GPU enabled (USB boots on any hardware)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Nix overlays - disabled for useGlobalPkgs compatibility
  # nixpkgs.overlays = [
  #   inputs.niri.overlays.niri
  #   inputs.llm-agents.overlays.default
  # ];

  # User — override ISO base's "nixos" auto-login to use j_kro
  users.users.j_kro = {
    isNormalUser = true;
    group = "j_kro";
    description = "Jeremy Kroeker";
    extraGroups = ["wheel" "networkmanager" "video" "render"];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [sshKey];
  };
  users.groups.j_kro = {};

  # Disable the ISO base's nixos user auto-login, use j_kro instead
  services.displayManager.autoLogin = {
    enable = true;
    user = "j_kro";
  };
  # Prevent nixos user from being auto-created by ISO base
  users.users.nixos = lib.mkForce {
    isNormalUser = true;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = [sshKey];
  };

  # SSH
  users.users.root = {
    openssh.authorizedKeys.keys = [sshKey];
  };
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "yes";
    };
  };

  security.sudo = {
    enable = true;
    extraConfig = ''
      j_kro ALL=(ALL) NOPASSWD: ALL
    '';
  };

  # Desktop / Niri
  programs.niri.enable = true;
  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/nord.yaml";
    image = ../../modules/desktop/wallpapers/nord-bg.png;
  };
  services.displayManager.sddm.enable = lib.mkForce true;

  # Home Manager — j_kro desktop setup (niri config + noctalia-shell)
  home-manager = {
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.j_kro = {pkgs, ...}: {
      imports = [
        ../../modules/home-manager/fish.nix
        ../../modules/home-manager/starship.nix
        ../../modules/home-manager/alacritty.nix
      ];
      home.stateVersion = "26.05";
    };
  };

  # NVIDIA NIM API key — for Hermes autonomous operation
  age.secrets.nvidia-api-key = {
    file = ../../secrets/nvidia-api-key.age;
    owner = "j_kro";
  };
  # Hermes Agent — self-contained config matching live setup
  environment.variables.HERMES_HOME = "/home/j_kro/.hermes";
  system.activationScripts.hermes-usb-setup = lib.stringAfter ["users"] ''
        HERMES_HOME="/home/j_kro/.hermes"
        mkdir -p "$HERMES_HOME"/{sessions,memories,skills,cron,logs}

        cat > "$HERMES_HOME/config.yaml" << 'YAML_EOF'
        model:
          default: qwen/qwen3.5-397b-a17b
          provider: nvidia

        providers:
          nvidia:
            base_url: https://integrate.api.nvidia.com/v1
            key_env: NVIDIA_API_KEY

        fallback_providers:
          - nvidia

        terminal:
          backend: local
          timeout: 180

        toolsets:
          - all

        memory:
          memory_enabled: true
          user_profile_enabled: true

        compression:
          enabled: true
          threshold: 0.9

        agent:
          max_turns: 90
          gateway_timeout: 1800
          api_max_retries: 3
      tool_use_enforcement: auto
    YAML_EOF

        # Load NVIDIA API key from agenix-decrypted secret into .env
        if [ -f "/run/agenix/nvidia-api-key" ]; then
          echo "NVIDIA_API_KEY=*** /run/agenix/nvidia-api-key)" > "$HERMES_HOME/.env"
          chmod 600 "$HERMES_HOME/.env"
        fi

      cat > "$HERMES_HOME/SOUL.md" << 'SOUL_EOF'
      You are Hermes Agent, an intelligent AI assistant. You are helpful,
      knowledgeable, and direct. You are running from a NixOS rescue USB.
    SOUL_EOF

        chown -R j_kro:j_kro "$HERMES_HOME"
        chmod 750 "$HERMES_HOME"
  '';

  # System Packages — Workstation + Rescue tools
  environment.systemPackages =
    [
      inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default
      rescue-scripts
    ]
    ++ (with pkgs; [
      # Shell & Terminal
      fish
      starship
      zoxide
      fzf
      eza
      btop
      htop
      tmux
      mosh
      bat
      ripgrep
      fd

      # Git + GitHub
      git
      gh

      # Development
      vim
      nano

      # Networking
      nmap
      dnsutils
      iproute2
      iputils
      net-tools
      curl
      wget
      httpie
      jq
      yq
      tcpdump
      mtr
      whois

      # NFS client for mounting config from Zephyr
      nfs-utils

      # Rescue / disk tools
      gparted
      parted
      e2fsprogs
      dosfstools
      btrfs-progs
      lvm2
      cryptsetup
      mdadm
      smartmontools
      nvme-cli
      xfsprogs
      jfsutils
      nilfs-utils
      f2fs-tools

      # Additional recovery tools
      efibootmgr
      gptfdisk
      iotop
      pciutils
      usbutils

      # NixOS tools
      inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena

      # Browser
      firefox

      # Desktop
      noctalia-shell

      # Rescue script
      rescue-script

      # Shell utilities
      bc
      rsync
      tree
      tokei
      dust

      # Compression
      unzip
      zip
      gzip
      xz
      bzip2
      p7zip

      # Media
      feh
      mpv
      imagemagick
      ffmpeg

      # Monitoring
    ]);

  # ZRAM (reduce writes on flash)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
    priority = 999;
  };

  # tmpfs /tmp to reduce flash writes
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = ["size=2G" "mode=1777" "nosuid" "nodev"];
  };

  system.stateVersion = "26.05";
}
