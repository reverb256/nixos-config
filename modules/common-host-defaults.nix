{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  disabledModules = ["${inputs.stylix}/modules/kmscon/nixos.nix"];
  system.stateVersion = lib.mkDefault "26.05";

  # Auto-cleanup old nix generations
  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "daily";
    options = lib.mkDefault "--delete-older-than 10d";
  };

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
    build-users-group = "nixbld";
    # Sandbox IS enabled. This is REQUIRED for correct builds: with
    # sandbox=false, Flutter/AOT packages (e.g. localsend) embed their
    # temporary build dir (/nix/var/nix/b/<hash>/b) in binary RPATHs, which
    # Nix rejects with "forbidden references" and the whole toplevel fails.
    # sandbox is a daemon-side setting — client --option sandbox true does NOT
    # propagate to remote builders (ssh-ng), so this MUST be true here.
    #
    # Lix flake-update curl bug (error 42 on GitHub API calls) is NOT an issue
    # for builds; only `nix flake update` is affected. Workaround: run
    # `nix flake update --option sandbox false` (see justfile `update` recipe).
    sandbox = true;
    # GitHub access token for flake input fetching (avoids API rate limiting)
    # Token is a fine-grained PAT with only metadata:read permissions.
    # Stored in sops-nix at secrets/ci/github-token.yaml
    # access-tokens removed — injected by nix-access-token.service from sops secret
  };

  # Prevent /boot partition from filling up
  boot.loader.systemd-boot = {
    enable = lib.mkDefault true;
    configurationLimit = 3;
    consoleMode = "auto";
    graceful = lib.mkDefault false;
    editor = lib.mkDefault false;
    # 2026-07-30: disabled to break python3->tkinter->tcl-8_6 eval chain
    edk2-uefi-shell.enable = lib.mkDefault false;
    memtest86.enable = lib.mkDefault true;
  };

  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

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
    git = {
      enable = lib.mkDefault true;
      config = {
        init.defaultBranch = "main";
        user.name = "j_kro";
        user.email = lib.mkDefault "j_kro@${config.networking.hostName or "cluster"}";
        # HTTPS git remotes read credentials from ~/.git-credentials
        # (provisioned by secretspec-creds from secrets/infra/git-credentials.yaml).
        credential.helper = lib.mkDefault "store";
      };
    };
    nix-ld.enable = lib.mkDefault true;
  };

  # ── Inject GitHub access token into nix.conf from sops secret ──
  # The placeholder token in nix.settings.access-tokens above is NOT used.
  # Instead, sops-nix decrypts secrets/ci/github-token.yaml to
  # /run/secrets/github-token at boot. This oneshot reads it and patches
  # nix.conf BEFORE nix-daemon starts, so GitHub API calls authenticate.
  systemd.services.nix-access-token = let
    script = pkgs.writeShellScript "nix-access-token" ''
      TOKEN_FILE="/run/secrets/github-token"
      NIX_CONF="/etc/nix/nix.conf"
      if [ -f "$TOKEN_FILE" ] && [ -r "$TOKEN_FILE" ]; then
        TOKEN=$(cat "$TOKEN_FILE" | tr -d '\n')
        if grep -q "^access-tokens" "$NIX_CONF" 2>/dev/null; then
          sed -i "s|^access-tokens =.*|access-tokens = github.com=$TOKEN|" "$NIX_CONF"
        else
          echo "access-tokens = github.com=$TOKEN" >> "$NIX_CONF"
        fi
      fi
    '';
  in {
    description = "Inject GitHub access token into nix.conf from sops secret";
    requiredBy = ["nix-daemon.service"];
    before = ["nix-daemon.service"];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${script}";
    };
  };
}
