{
  pkgs,
  pkgsWithOverlay,
  inputs,
}: let
  llama-cpp-turboquant = inputs.llama-turboquant.packages.x86_64-linux.llama-cpp-turboquant;
  cluster = import ./cluster.nix;
  easykubenix = import inputs.easykubenix {
    inherit pkgs;
    modules = [
      {_module.args.pkgsWithOverlay = pkgsWithOverlay;}
      {_module.args.llama-cpp-turboquant = llama-cpp-turboquant;}
      {_module.args.inputs = inputs;}
      {_module.args.cluster = cluster;}
      # HA affinity: prefer nexus, failover to sentry. Used by stateless deployments.
      {_module.args.nexusPreferredAffinity = {
        nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution = [
          {
            weight = 80;
            preference.matchExpressions = [{
              key = "kubernetes.io/hostname";
              operator = "In";
              values = ["nexus" "sentry"];
            }];
          }
          {
            weight = 50;
            preference.matchExpressions = [{
              key = "kubernetes.io/hostname";
              operator = "In";
              values = ["nexus"];
            }];
          }
        ];
      };}
      # nix-csi disabled — CSI volumes use hostPath/nix mounts directly
      # See modules/nix-csi-README.md for upstream CSI driver details
      ./modules/common.nix
      ./modules/infrastructure.nix
      ./modules/mining.nix
      ./modules/gpu-miners.nix
      ./modules/profit-switcher.nix
      ./modules/gpu-tuning.nix
      ./modules/ai-inference.nix
      ./modules/llama-servers.nix
      ./modules/nixkube.nix
      ./modules/searxng.nix
      ./modules/haven.nix
      ./modules/casdoor.nix
      ./modules/oauth2-proxy.nix
      ./modules/monitoring.nix
      ./modules/monitoring-dashboards.nix
      ./modules/vane.nix
      ./modules/host-services.nix
      ./modules/ai-coding-tools.nix
      ./modules/mission-control.nix
      ./modules/kagent.nix
      ./modules/automation.nix
      ./modules/mcp-servers.nix
    ];
  };
in
  easykubenix
