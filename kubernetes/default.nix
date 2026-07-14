{
  lib,
  pkgs,
  pkgsWithOverlay,
  inputs,
}: let
  cluster = import ./cluster.nix;

  # Common args passed to all modules
  commonModules = [
    {_module.args.pkgsWithOverlay = pkgsWithOverlay;}

    {_module.args.inputs = inputs;}
    {_module.args.cluster = cluster;}
    {_module.args.aiModelsToml = ./ai-models.toml;}
    {_module.args.aiModelRegistry = ./curated-models.nix;}
    {
      _module.args.nexusPreferredAffinity = {
        nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution = [
          {
            weight = 80;
            preference.matchExpressions = [
              {
                key = "kubernetes.io/hostname";
                operator = "In";
                values = ["nexus" "sentry"];
              }
            ];
          }
          {
            weight = 50;
            preference.matchExpressions = [
              {
                key = "kubernetes.io/hostname";
                operator = "In";
                values = ["nexus"];
              }
            ];
          }
        ];
      };
    }
    ./modules/common.nix
  ];

  # Helper to create an easykubenix instance for a set of modules
  # NOTE: easykubenix is vendored locally to avoid GitHub fetch hangs.
  mkManifest = name: modules: let
    easykubenix = import ../vendor/easykubenix {
      inherit pkgs;
      modules = commonModules ++ modules;
    };
  in
    easykubenix;
in {
  # Legacy combined manifest (for backwards compatibility)
  combined =
    mkManifest "combined" [
      ./modules/infrastructure.nix
    ]
    ++ lib.optional (inputs ? mining-infra) inputs.mining-infra.kubernetes.modules
    ++ [
      ./modules/gpu-tuning.nix
      ./modules/ai-inference.nix
      ./modules/llama-servers.nix
      ./modules/nixkube.nix
      ./modules/searxng.nix
      ./modules/vane.nix
      ./modules/haven.nix
      ./modules/casdoor.nix
      ./modules/cert-manager.nix
      ./modules/oauth2-proxy.nix
      ./modules/monitoring.nix
      ./modules/monitoring-dashboards.nix
      ./modules/vane.nix
      ./modules/host-services.nix
      ./modules/mission-control.nix
      ./modules/automation.nix
      ./modules/mcp-servers.nix
      ./modules/glance.nix
      ./modules/hermes-workspace.nix
      ./modules/maplespike.nix
      ./modules/tailscale.nix
    ];

  # Separate manifests for large modules (to avoid eval bottleneck)
  monitoring = mkManifest "monitoring" [
    ./modules/monitoring.nix
    ./modules/monitoring-dashboards.nix
    ./modules/llama-servers.nix
  ];

  ai-inference = mkManifest "ai-inference" [
    ./modules/ai-inference.nix
  ];

  host-services = mkManifest "host-services" [
    ./modules/host-services.nix
  ];

  llama-servers = mkManifest "llama-servers" [
    ./modules/llama-servers.nix
  ];

  # Mining from isolated flake
  mining = mkManifest "mining" ((lib.optional (inputs ? mining-infra) inputs.mining-infra.kubernetes.modules)
    ++ [
      ./modules/profit-switcher.nix
    ]);

  frostbite = mkManifest "frostbite" [
    ./modules/frostbite-gazette.nix
  ];

  # Small modules combined
  small = mkManifest "small" [
    ./modules/infrastructure.nix
    ./modules/gpu-tuning.nix
    ./modules/nixkube.nix
    ./modules/searxng.nix
    ./modules/haven.nix
    ./modules/casdoor.nix
    ./modules/cert-manager.nix
    ./modules/oauth2-proxy.nix
    ./modules/vane.nix
    ./modules/maplespike.nix
    ./modules/mission-control.nix
    ./modules/mcp-servers.nix
    ./modules/glance.nix
    ./modules/hermes-workspace.nix
    ./modules/tailscale.nix
    ./modules/llama-servers.nix
    ./modules/falco.nix
  ];

  kubevirt = mkManifest "kubevirt" [
    ./modules/kubevirt.nix
  ];
}
