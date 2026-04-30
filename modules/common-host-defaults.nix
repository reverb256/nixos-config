{
  config,
  lib,
  pkgs,
  ...
}: {
  system.stateVersion = "26.05";

  time.timeZone = lib.mkDefault "UTC";

  services = {
    ssh-ca.enable = lib.mkDefault true;
    logind.settings = {
      Login = {
        KillUserProcesses = lib.mkDefault false;

        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";

        HandlePowerKey = "ignore";

        HandleSuspendKey = "ignore";

        HandleHibernateKey = "ignore";

        IdleAction = "ignore";
        IdleActionSec = "0";

        HoldoffTimeoutSec = "0";
      };
    };

    displayManager = {
      sddm = {
        enable = lib.mkOverride 1499 false;
        wayland.enable = lib.mkOverride 1499 false;
      };
      autoLogin = {
        enable = lib.mkOverride 1499 false;
        user = lib.mkDefault "j_kro";
      };
    };

    whisper-dictation = lib.mkDefault {
      enable = true;
      model = "base.en";
      language = "en";
      injectionMode = "both";
      keyDelay = 10;
      notify = true;
      silenceTimeout = 1.5;
      silenceThreshold = "5%";
    };

    backup-to-garage.enable = lib.mkDefault false;

    rclone-sync.enable = lib.mkDefault false;

    gaming-detection.enable = lib.mkDefault false;
    gpu-profile-manager.enable = lib.mkDefault false;
    mining-coordinator.enable = lib.mkDefault false;
  };

  hardware.gpu-compute.enable = lib.mkDefault false;
  hardware.gpu-compute.vulkan.enable = lib.mkDefault false;
  hardware.gpu-compute.cuda.enable = lib.mkDefault false;

  nix.settings = {
    trusted-users = ["j_kro"];
  };

  boot.loader = {
    systemd-boot.enable = lib.mkDefault true;

    efi.canTouchEfiVariables = lib.mkDefault true;

    systemd-boot.graceful = lib.mkDefault false;

    systemd-boot.configurationLimit = lib.mkDefault 20;

    systemd-boot.editor = lib.mkDefault false;

    systemd-boot.edk2-uefi-shell.enable = lib.mkDefault true;

    systemd-boot.memtest86.enable = lib.mkDefault true;
  };

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_zen;

  networking.firewall = {
    allowedTCPPortRanges = lib.mkOptionDefault [
      {
        from = 30000;
        to = 32767;
      }
    ];

    allowedUDPPorts = lib.mkOptionDefault [
      8472
    ];
  };

  programs = {
    sleepy-launcher.enable = lib.mkDefault true;
    git = {
      enable = lib.mkDefault true;
      config = {
        init.defaultBranch = "main";
        user.name = "j_kro";
        user.email = lib.mkDefault "j_kro@${config.networking.hostName or "cluster"}";
      };
    };
    nix-ld.enable = lib.mkDefault true;
  };
}
