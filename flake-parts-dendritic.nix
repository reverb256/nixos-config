{
  description = "Reverb-OS NixOS Cluster - Dendritic Flake-Parts Architecture";

  inputs = {
    # Core Nix dependencies
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-xr.url = "github:nix-community/nixpkgs-xr";
    nixpkgs-xr.inputs.nixpkgs.follows = "nixpkgs";

    # flake-parts for modular architecture
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # External modules and packages
    zen-browser.url = "github:0xc000022070/zen-browser-flake/e97c8e719c7e2567ccf86d279f73ade1dbf72373";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
    zen-browser.inputs.home-manager.follows = "home-manager";

    ezkea.url = "github:ezKEa/aagl-gtk-on-nix";
    nixcord.url = "github:FlameFlag/nixcord";
    nix-gaming.url = "github:fufexan/nix-gaming";
    scopebuddy.url = "github:OpenGamingCollective/ScopeBuddy";
    scopebuddy.inputs.nixpkgs.follows = "nixpkgs";

    claude-native.url = "github:ryoppippi/claude-code-overlay";
    claude-native.inputs.nixpkgs.follows = "nixpkgs";

    # Secrets and deployment
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    nix-cachyos-kernel.url = "github:drakon64/nixos-cachyos-kernel";

    # Nix tools
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    # OpenCode AI Agent
    opencode.url = "github:anomalyco/opencode/dev";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];

      imports = [
        # Dendritic module structure
        ./dendritic-modules
      ];

      perSystem = {
        pkgs,
        system,
        ...
      }: {
        # Shared overlays
        _module.args.pkgs = import nixpkgs {
          inherit system;
          overlays = [
            self.overlays.default
          ];
          config.allowUnfree = true;
        };

        # Shared overlays
        overlays = {
          default = import ./modules/mining-overlay.nix;

          # Add nixpkgs-xr overlay for VR/gaming packages
          nixpkgs-xr = inputs.nixpkgs-xr.overlays.default;

          # Claude Code overlay
          claude = _: _: {
            claude = inputs.claude-native.packages.${system}.default;
          };
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          name = "nixos-config-dendritic";

          packages = with pkgs; [
            # Nix tools
            nixfmt-tree
            alejandra
            deadnix
            statix
            nixd

            # Git tools
            git
            gh

            # Build tools
            just
            colmena

            # Secrets management
            age
            ssh-to-age
            sops

            # Cloud/Cache tools
            minio-client
            rclone

            # System tools
            jq
            yq
            curl
            wget

            # Script quality
            shellcheck

            # Documentation
            mdsh
          ];

          shellHook = ''
            echo "🚀 NixOS Config Development Environment (Dendritic)"
            echo ""
            echo "Available commands:"
            echo "  just              - Run just recipes"
            echo "  colmena           - Deploy to cluster"
            echo "  deadnix .         - Find dead Nix code"
            echo "  statix check .    - Lint Nix files"
            echo "  alejandra .       - Format Nix files"
            echo "  shellcheck .      - Check shell scripts"
            echo "  mc                - MinIO client"
            echo ""
            echo "Hosts: zephyr, nexus, forge, sentry"
            echo "Cache: http://10.1.1.120:9000 (nexus AIStor)"
          '';
        };

        # Formatter
        formatter = pkgs.nixfmt-tree;

        # Packages
        packages.claude = inputs.claude-native.packages.${pkgs.system}.default;
      };
    };
}
