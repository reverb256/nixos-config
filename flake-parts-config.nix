{
  inputs,
  pkgs,
}: {
  imports = [
    ./hosts/zephyr/configuration.nix
    ./hosts/nexus/configuration.nix
    ./hosts/forge/configuration.nix
    ./hosts/sentry/configuration.nix
  ];

  nixosConfigurations = {
    zephyr = {
      modules = [
        {
          networking.hostName = "zephyr";

          # ============================================================================
          # STEAM - Full VR Support with NVENC Optimizations
          # ============================================================================
          programs.steam = {
            enable = true;
            extraCompatPackages = with pkgs; [
              inputs.nixpkgs-xr.packages.x86_64-linux.proton-ge-bin
              inputs.nixpkgs-xr.packages.x86_64-linux.proton-ge-rtsp-bin
            ];
          };

          # ============================================================================
          # WI VRN - Wireless VR Streaming for Quest Pro
          # ============================================================================
          services.wivrn = {
            enable = true;
            openFirewall = true;
            defaultRuntime = true;
            config.enable = true;
            config.json = {
              # Quest Pro specific optimizations for 90Hz target
              device = {
                name = "Quest Pro";
                type = "quest_pro";
                # High resolution for Quest Pro at 90Hz
                resolution = "1800x1920"; # Native Quest Pro resolution per eye
                refresh_rate = 90;
              };

              # Streaming optimizations for RTX 3090 at 90Hz
              stream = {
                codec = "hevc"; # HEVC for better compression at 90Hz
                targetBitrate = 150; # Optimized bitrate for RTX 3090 at 90Hz (Mbps)
                spatial = true; # Enable spatial encoding
                temporal = true; # Enable temporal encoding
                encoder = "nvenc"; # Use NVIDIA NVENC for hardware acceleration
                postprocess = true; # Enable post-processing
              };

              # Network optimizations for 90Hz streaming
              network = {
                port = 9757;
                portRange = [9757 9760];
                udp = true;
                tcp = true;
              };

              # Quest Pro display settings
              display = {
                forceColorSpace = "sRGB";
                forceColorRange = "Full";
              };
            };
          };

          # ============================================================================
          # GAMEMODE - Performance Optimization
          # ============================================================================
          services.gamemode = {
            enable = true;
            use_systemd = true;
            softrealtime = "auto"; # Use SCHED_ISO when available
            renice = 15; # Increase priority for gaming processes
            ioprio = 0; # Highest I/O priority
          };

          # ============================================================================
          # NVIDIA VR OPTIMIZATIONS - NVENC, Low Latency, VR Ready
          # ============================================================================
          hardware.graphics.enable = true;

          # NVIDIA power management and performance
          boot.extraModprobeConfig = ''
            # NVIDIA VR optimizations for RTX 3090
            options nvidia "NVreg_RegistryDwords=RMIntrLockingMode=1;NVreg_EnableResizableBar=1;NVreg_EnableGpuFirmware=1"
            options nvidia-uvm "uvm_perf_prefetch_enable=1"
          '';

          # ============================================================================
          # PACKAGES - VR Applications and Tools
          # ============================================================================
          environment.systemPackages = with pkgs; [
            # VR runtimes and tools
            wivrn
            openxr-loader

            # SteamVR support
            steam-run

            # Performance monitoring and optimization tools
            gamescope
            mangohud
            goverlay
            nvtopPackages.full

            # Gaming performance tools
            gamemode

            # Enhanced Claude Code environment
            inputs.claude-native.packages.x86_64-linux.default
          ];

          # ============================================================================
          # ASSERTIONS - VR Configuration Validation
          # ============================================================================
          assertions = [
            {
              assertion = config.programs.steam.enable;
              message = "Steam must be enabled for VR support";
            }
            {
              assertion = config.services.wivrn.enable;
              message = "WiVRn must be enabled for VR support";
            }
            {
              assertion = config.hardware.graphics.enable;
              message = "NVIDIA graphics must be enabled for optimal VR performance";
            }
          ];

          # Anime game launchers (workstation only)
          programs.anime-game-launcher.enable = true;
          programs.honkers-railway-launcher.enable = true;
          programs.sleepy-launcher.enable = true;
        }
        inputs.ezkea.nixosModules.default
        inputs.agenix.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.j_kro = {
            imports = [./home.nix];
          };
        }
      ];
    };

    nexus = {
      modules = [
        {
          networking.hostName = "nexus";
        }
        inputs.ezkea.nixosModules.default
        inputs.agenix.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.j_kro = {
            imports = [./home.nix];
          };
        }
      ];
    };

    forge = {
      modules = [
        ./configuration.nix
        ./hosts/forge/hardware-configuration.nix
        {
          networking.hostName = "forge";
        }
        inputs.ezkea.nixosModules.default
        inputs.agenix.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.j_kro = {
            imports = [./home.nix];
          };
        }
      ];
    };

    sentry = {
      modules = [
        {
          networking.hostName = "sentry";
        }
        inputs.ezkea.nixosModules.default
        inputs.agenix.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.j_kro = {
            imports = [./home.nix];
          };
        }
      ];
    };
  };

  overlays = [
    inputs.self.overlays.mining-overlay
    (inputs.claude-native.overlay or (_: _: {}))
    (final: _prev: {
      # Enhanced Claude Code with MCP support
      inherit (final) claude;
    })
  ];

  config = {
    # Common Nix configuration for all hosts
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      max-jobs = 8;
      cores = 16;
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://ezkea.cachix.org"
        "https://nixpkgs-wayland.cachix.org"
        "https://nix-gaming.cachix.org"
        "https://cuda-maintainers.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
        "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
        "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      ];
    };
  };
}
