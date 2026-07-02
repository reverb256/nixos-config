# Portable NixOS USB - Full system with Niri desktop
# Built from your nixos-config with all projects
#
# To build:
#   sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress
#
# Or use nixos-generate --format sd-x86_64
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-mineral = {
      url = "github:cynicsketch/nix-mineral";
    };
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    nixosConfigurations.portable-usb = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs;};
      modules = [
        home-manager.nixosModules.home-manager
        niri.nixosModules.niri

        # ─────────────────────────────────────────────────────────
        # FULL SYSTEM CONFIG
        # ─────────────────────────────────────────────────────────
        {
          # ─── Network ────────────────────────────────────────
          networking = {
            hostName = "portable-nixos";
            networkmanager.enable = true;
            wireless.enable = true;
            firewall.enable = false; # Portable, more flexible
          };

          # ─── User ───────────────────────────────────────────
          users.users.j_kro = {
            isNormalUser = true;
            description = "Portable NixOS User";
            extraGroups = ["wheel" "networkmanager" "docker" "kvm"];
            # Add your SSH keys here:
            # openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC..." ];
          };

          # ─── Services ───────────────────────────────────────
          services = {
            openssh = {
              enable = true;
              settings = {
                PermitRootLogin = "yes";
                PasswordAuthentication = true;
              };
            };
            xserver.enable = true;
            displayManager = {
              sddm.enable = true;
              defaultSession = "niri";
            };
          };

          # ─── Niri Desktop ────────────────────────────────────
          programs = {
            niri.enable = true;
            uwsm = {
              enable = true;
              waylandCompositors.niri = {
                prettyName = "Portable Niri";
                comment = "Niri - Your scrollable-tiling Wayland compositor";
                binPath = "/run/current-system/sw/bin/niri-session";
              };
            };
            fish = {
              enable = true;
              interactiveShellInit = ''
                starship init fish | source
              '';
            };
            starship = {
              enable = true;
            };
          };

          # ─── Basic Packages ────────────────────────────────────
          environment.systemPackages = with pkgs; [
            # Core utils
            git
            vim
            tmux
            fish
            starship
            eza
            bat
            ripgrep
            fd
            fzf
            curl
            wget
            httpie
            gh

            # Development
            # nix
            # colmena

            # Network
            iproute2
            iputils
            dnsutils
            nettools
            whois
            mtr
            tcpdump
            nmap

            # Monitoring
            htop
            btop
            nvtop

            # Browser
            # firefox-unwrapped

            # Shell utils
            bc
            rsync
            tree
            jq
            yq
            tokei
            dust

            # Compression
            unzip
            zip
            tar
            gzip
            xz
            bzip2
            p7zip

            # Media
            feh
            mpv
            imagemagick
            ffmpeg

            # Fonts
            nerdfonts
          ];

          # ─── Fonts & Theming ───────────────────────────────
          fonts.fonts = with pkgs.nerdfonts; [
            JetBrainsMono
            FiraCode
            Hack
            SourceCodePro
          ];

          # ─── Boot ──────────────────────────────────────────
          boot = {
            loader = {
              systemd-boot.enable = true;
              efi.canTouchEfiVariables = true;
            };
            kernelParams = [
              "quiet"
              "loglevel=3"
            ];
          };

          # ─── Filesystem ─────────────────────────────────────
          # USB will be the root
          # Configure after installation based on actual drive

          # ─── Timezone & Locale ──────────────────────────────
          time.timeZone = "America/Winnipeg";
          i18n.defaultLocale = "en_US.UTF-8";

          # ─── Hardware ─────────────────────────────────────
          hardware.nvidia = {
            enable = true;
            open = false;
            modesetting.enable = true;
          };
          hardware.opengl = {
            enable = true;
            driSupport = true;
          };

          # ─── Nix ─────────────────────────────────────────
          nix = {
            settings = {
              substituters = [
                "https://niri.cachix.org"
                "https://noctalia.cachix.org"
                "https://nix-community.cachix.org"
              ];
              trusted-public-keys = [
                "niri.cachix.org-1:Wv0O6Tz6V5fM6gD8hIRwM+QjRtBu5OD5QyQjx2hE8vE="
                "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
                "nix-community.cachix.org-1:3B8gQfk+egR5f2cK5zJqHmWqJdY6LlBBwRiAxH2wX5o="
              ];
              max-jobs = "auto";
              cores = 0; # Use all available
            };
            package = pkgs.nix;
            nixPath = "nixpkgs=https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
          };

          # ─── Environment ─────────────────────────────────
          environment.sessionVariables = {
            # Add your env vars here
            # EDITOR = "vim";
            # VISUAL = "code";
          };

          # ─── Security (minimal for portable) ───────────────
          security = {
            sudo.wheelNeedsPassword = false;
            doas.enable = false;
          };

          # ─── System ────────────────────────────────────────
          system = {
            stateVersion = "25.05";
            autoUpgrade.enable = false;
          };
        }
      ];
    };
  };
}
