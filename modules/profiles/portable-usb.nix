{
  config,
  lib,
  pkgs,
  modulesPath,
  inputs,
  ...
}: let
  # Portable USB rescue + pinch-work stick — prototyped against the
  # wayfinder contract (map #421, decisions #422/#423/#425/#426).
  #
  # Produces a GPT disk image via systemd-repart (nixpkgs image/repart.nix),
  # following the NixOS Manual §Appliance Image pattern:
  #   - esp partition (vfat): systemd-boot copied to the removable fallback
  #     path EFI/BOOT/BOOTX64.EFI (boots on any UEFI firmware without host
  #     NVRAM entries), plus a Unified Kernel Image at EFI/Linux/nixos.efi.
  #   - root partition (ext4, label "nixos") with the system toplevel
  #     closure inline via storePaths — the stick carries its own store,
  #     satisfying the rescue closure-carry requirement (#243).
  #
  # Build (on the nexus builder, never zephyr-local — OOM guard):
  #   nix build .#nixosConfigurations.portable.config.system.build.image
  #   sudo dd if=result/portable.raw of=/dev/disk/by-id/usb-... bs=4M status=progress oflag=sync
  meshKeys = import ../../mesh-keys.nix;
in {
  imports = [
    "${modulesPath}/image/repart.nix"
    ../../modules/hardware/gpu-compute.nix
    ../../modules/desktop/niri.nix
  ];

  # Apply the repo's overlays (bugfixes re-adds libdisplay-info_0_2 that the
  # niri-flake overlay still requires after the nixpkgs bump).
  nixpkgs.overlays = [
    (import ../../overlays/default.nix { inherit inputs; })
  ];

  # ── Image definition (systemd-repart) ──
  image.repart = {
    name = "portable";
    imageSize = "auto";
    partitions = {
      "esp" = {
        contents = {
          "/EFI/BOOT/BOOTX64.EFI".source =
            "${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootx64.efi";
          "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
            "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
        };
        repartConfig = {
          Type = "esp";
          Format = "vfat";
          SizeMinBytes = "96M";
        };
      };
      "root" = {
        storePaths = [config.system.build.toplevel];
        repartConfig = {
          Type = "root";
          Format = "ext4";
          Label = "nixos";
          Minimize = "guess";
        };
      };
    };
  };

  # ── Boot: match the image layout; never touch host NVRAM ──
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  boot.kernelParams = [
    "quiet"
    "loglevel=3"
    "console=ttyS0,115200n8"
  ];

  # Storage drivers for hardware-agnostic boot (USB stick on any host,
  # plus virtio for QEMU smoke-testing). Without these the initrd cannot
  # see the root disk and drops to emergency mode.
  boot.initrd.kernelModules = [
    "usb_storage"
    "uas"
    "usbhid"
    "nvme"
    "ahci"
    "sd_mod"
    "virtio_blk"
    "virtio_pci"
    "virtio_scsi"
  ];

  # ── Storage: tmpfs /tmp keeps flash wear down; zram for swap ──
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = ["mode=1777" "size=1G"];
  };
  zramSwap.enable = lib.mkDefault true;

  # ── GPU: universal module, no vendor hardcode (#423) ──
  hardware.graphics.enable = true;
  hardware.gpu-compute.enable = true;
  # Vulkan ICDs for both vendors; heavy CUDA/ROCm stay out of this boot
  # closure (contract #425: minimal; dev-shell can add them later).
  hardware.gpu-compute.vulkan.enable = true;

  # ── Desktop / pinch-work: niri + SDDM autologin ──
  programs.niri.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "j_kro";
  };
  services.displayManager.defaultSession = "niri";

  # ── Login: j_kro with mesh keys (the cluster's declared set) ──
  users.users.j_kro = {
    isNormalUser = true;
    hashedPassword = "!";
    openssh.authorizedKeys.keys = meshKeys;
    extraGroups = ["wheel" "networkmanager" "users"];
  };
  users.users.root.openssh.authorizedKeys.keys = meshKeys;

  # Passwordless sudo for a throwaway stick we own; ssh stays key-only.
  security.sudo.wheelNeedsPassword = false;

  # ── Remote: key-only SSH, mDNS announce for pinch work ──
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      userServices = true;
      addresses = true;
    };
  };
  networking.networkmanager.enable = true;

  # ── Rescue toolkit embedded (426 A8; design doc) ──
  environment.etc = {
    "rescue/cli.sh".text = builtins.readFile ../../scripts/rescue/rescue-cli.sh;
    "rescue/runbook.md".text = builtins.readFile ../../docs/runbooks/nixos-usb-rescue.md;
  };

  # ── Nix on the stick: official cache + self-contained store ──
  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrWdURt2TtbV2y1g99lkAQy4U="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  environment.systemPackages = with pkgs; [
    # rescue + diagnostics
    btrfs-progs
    cryptsetup
    mdadm
    lvm2
    parted
    gptfdisk
    dosfstools
    xfsprogs
    e2fsprogs
    nfs-utils
    # shell / pinch work
    git
    ripgrep
    fd
    fzf
    starship
    fish
    tmux
    htop
    neovim
    curl
    wget
    jq
    # GPU observation
    vulkan-tools
    pciutils
  ];

  system.stateVersion = "25.05"; # sticky: matches repo channel
  time.timeZone = "America/Winnipeg";
}