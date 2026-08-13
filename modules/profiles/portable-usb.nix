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
  #   nix build .#portable-image
  #   sudo dd if=result/portable.raw of=/dev/disk/by-id/usb-... bs=4M status=progress oflag=sync
  meshKeys = import ../../mesh-keys.nix;

  # The portable image has no checked-in model payload. Keep the model
  # integration optional so pure flake evaluation never reads a host path.
  modelAvailable = false;
  bonsaiModel = null;

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
        # The toplevel carries /etc (populated at boot by activation) and the
        # store closure. The Bonsai model is symlinked into place via a
        # tmpfiles rule (see systemd.tmpfiles.rules) that references bonsaiModel.
        storePaths = [
          config.system.build.toplevel
        ];
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
  # CUDA runtime pulls in unfree CUDA EULA packages; the stick is a personal
  # throwaway so allowUnfree is acceptable here (Vulkan is the primary runner).
  nixpkgs.config.allowUnfree = true;
  hardware.graphics.enable = true;
  hardware.gpu-compute.enable = true;
  # Vulkan ICDs for both vendors (universal runner for all 7 GPUs).
  hardware.gpu-compute.vulkan.enable = true;
  # CUDA runtime libs on the stick (NVIDIA hosts can run CUDA tools directly).
  hardware.gpu-compute.cuda.enable = true;

  # ── Desktop / pinch-work: niri + Noctalia shell + SDDM autologin ──
  programs.niri.enable = true;
  # Noctalia (native Wayland bar/notifications/launcher) launched via XDG
  # autostart (version-proof; does not depend on the niri module config schema).
  programs.noctalia.enable = true;
  programs.noctalia.systemd.enable = lib.mkForce false;
  environment.sessionVariables.NOCTALIA_CONFIG_HOME = "/etc";
  environment.etc."xdg/autostart/noctalia.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Noctalia
    Exec=noctalia
    Comment=Native Wayland shell (bar/notifications/launcher)
    X-GNOME-Autostart-enabled=true
  '';
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

  # ── Local AI inference: 1-bit Bonsai 27B on Vulkan + Hermes ──
  # Symlink the embedded model (in /nix/store via bonsaiModel) to the fixed
  # path the service expects, created at boot by tmpfiles.
  systemd.tmpfiles.rules = lib.mkIf modelAvailable [
    "L+ /models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf - - - - ${bonsaiModel}/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf"
  ];
  # llama-cpp-vulkan serves it on 127.0.0.1:8080; Hermes points at that.
  systemd.services.bonsai-local = lib.mkIf modelAvailable {
    description = "Local Bonsai 27B 1-bit inference (Vulkan)";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      User = "j_kro";
      ExecStart = lib.getExe (pkgs.callPackage ../../packages/llama-cpp-vulkan.nix { })
        + " -m /models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf"
        + " --host 127.0.0.1 --port 8080 -ngl 99 -fa on"
        + " -c 131072 --cache-type-k q4_0 --cache-type-v q4_0 --fit off"
        + " --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 --jinja --parallel 1"
        + " --alias bonsai-27b-1bit-local";
      Restart = "on-failure";
      RestartSec = "10";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
  # Hermes desktop client: point at the local Bonsai server.
  environment.etc."hermes/config.toml" = lib.mkIf modelAvailable {
    text = ''
    [models.local]
    name = "bonsai-27b-1bit-local"
    provider = "openai"
    base_url = "http://127.0.0.1:8080/v1"
    api_key = "sk-local"
    context_length = 131072
    default = true

    [providers.local]
    type = "openai"
    base_url = "http://127.0.0.1:8080/v1"
    api_key = "sk-local"
    '';
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
    # AI inference runner (Vulkan backend — NVIDIA + AMD)
    (pkgs.callPackage ../../packages/llama-cpp-vulkan.nix { })
    # Hermes desktop client, configured for local inference
    (pkgs.callPackage ../../packages/hermes-chat.nix { })
  ];

  system.stateVersion = "25.05"; # sticky: matches repo channel
  time.timeZone = "America/Winnipeg";
}
