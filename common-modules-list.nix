{
  inputs,
  self,
}: [
  inputs.home-manager.nixosModules.home-manager
  ./modules/system/home-manager.nix
  inputs.aagl.nixosModules.default
  ./modules/desktop/aagl.nix
  inputs.nur.modules.nixos.default
  inputs.sops-nix.nixosModules.default
  ./modules/system/sops-secrets-registry.nix
  inputs.hermes-agent.nixosModules.default

  inputs.mcp-registry.nixosModules.default

  inputs.caddy-ingress.nixosModules.caddy
  inputs.caddy-ingress.nixosModules.caddy-common

  inputs.ai-gateway.nixosModules.default
  # REMOVED: compute-market (all mining infra switched to peakminer)
  inputs.gpu-proxy.nixosModules.default

  inputs.stylix.nixosModules.default
  ./modules/desktop/stylix.nix

  ./modules/services/peakminer.nix

  # Phase 4 closure: secretspec + sudo systemd-creds + LoadCredentialEncrypted=
  ./modules/services/secretspec-example.nix

  # cluster.localSealSupport module removed (Phase 1b/1c, 2026-07-25).
  # The cachix-fork secretspec is now a flake input (Phase 1a) — impure-eval
  # coupling is no longer needed. The module file is kept as a stub for
  # historical drift-cycle tracking (.plans/2026-07-25-cluster-localSealSupport-scope.md)
  # but is no longer imported here.

  ./modules/default.nix

  {
    # D-Bus configuration system (required by Stylix / HM dconf activation)
    programs.dconf.enable = true;
  }

  {
    nixpkgs.overlays = [
      inputs.niri.overlays.niri
      inputs.llm-agents.overlays.shared-nixpkgs
      self.overlays.default
      # secretspec-provider-sops: Phase 2 closure of the sops-nix → SecretSpec
      # migration. Exposed as `pkgs.secretspec-provider-sops` across all hosts.
      (final: prev: {
        secretspec-provider-sops = final.callPackage ./pkgs/secretspec-provider-sops { inherit inputs; };
      })
      inputs.lsfg-vk-nix.overlays.default
    ];
  }
]
