# Recovery USB with Niri Desktop
# Full NixOS recovery environment with Niri desktop
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Reverb256 projects
    # hermes-agent input REMOVED (issue #334) — provided by user nix profile.
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      config.cudaSupport = true;
    };
  in {
    nixosConfigurations.recovery-usb = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs;};
      modules = [
        home-manager.nixosModules.home-manager
        niri.nixosModules.niri

        # Core configuration for recovery
        {
          # Basic users
          users.users.j_kro = {
            isNormalUser = true;
            description = "Recovery User";
            extraGroups = ["wheel" "networkmanager"];
            openssh.authorizedKeys.keys = [
              # Cluster SSH key for automated recovery from the GH runner on nexus
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFGFHqWyZE0fadxRlfCFf/hyahjiS9WzlIvLkYf0ZK9b j_kro@nixos-cluster"
            ];
          };

          # Network
          networking = {
            hostName = "recovery-usb";
            networkmanager.enable = true;
            wireless.enable = true;
          };

          # Services
          services = {
            openssh = {
              enable = true;
              settings.PermitRootLogin = "yes";
              settings.PasswordAuthentication = true;
            };
            xserver.enable = true;
            displayManager = {
              sddm.enable = true;
              defaultSession = "niri";
            };
          };

          # Programs
          programs = {
            niri = {
              enable = true;
              settings = {
                # Niri will auto-detect
              };
            };
            uwsm = {
              enable = true;
              waylandCompositors.niri = {
                prettyName = "Niri Recovery";
                comment = "Niri Scrollable Tiling - Recovery Environment";
                binPath = "/run/current-system/sw/bin/niri-session";
              };
            };
          };

          # Basic packages for recovery
          environment.systemPackages = with pkgs; [
            git
            vim
            tmux
            htop
            curl
            wget
            starship
            eza
            bat
            ripgrep
            fd
            fzf
            # Browser for docs
            firefox
            # Build tools
            nix
            nix-tree
            nix-index
            # Cluster tools
            colmena
            # Network tools
            iputils
            iproute2
            dnsutils
            nettools
            # GitHub CLI
            gh
          ];

          # Boot
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;

          # Filesystems
          fileSystems."/".device = "/dev/sda1";
          fileSystems."/boot" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };

          # Swap
          swapDevices = [
            {device = "/dev/sda2";}
          ];

          # Timezone
          time.timeZone = "America/Winnipeg";

          # Locale
          i18n.defaultLocale = "en_US.UTF-8";

          # Console
          console = {
            font = "Lat15-Fixed16.psfu";
            keyMap = "us";
          };
        }
      ];
    };
  };
}
