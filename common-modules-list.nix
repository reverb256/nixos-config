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

  # cluster.localSealSupport — opt-in impure-eval for hosts with the local
  # cachix-fork checkout. See module header for rationale. Keep this AFTER
  # secretspec-* modules so it can override `nix.settings` if both stanzas
  # are merged by some future code-path.
  ./modules/system/secretspec-cluster-mode.nix

  ./modules/default.nix

  {
    nixpkgs.overlays = [
      inputs.niri.overlays.niri
      inputs.llm-agents.overlays.shared-nixpkgs
      self.overlays.default
      # secretspec-provider-sops: Phase 2 closure of the sops-nix → SecretSpec
      # migration. Exposed as `pkgs.secretspec-provider-sops` across all hosts.
      (final: prev: {
        secretspec-provider-sops = final.callPackage ./pkgs/secretspec-provider-sops {};
      })
      inputs.lsfg-vk-nix.overlays.default
    ];
  }
]
