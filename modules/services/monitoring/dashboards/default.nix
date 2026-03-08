# Declarative Dashboard Registry
# Imports all dashboard modules and provides them to Grafana
{lib, ...}: let
  # Import individual dashboard files
  masterOverview = import ./master-overview.nix {inherit lib;};
  deepInsights = import ./deep-insights.nix {inherit lib;};
  mining = import ./mining.nix {inherit lib;};
  gpuMonitoring = import ./gpu-monitoring.nix {inherit lib;};
  aiInference = import ./ai-inference.nix {inherit lib;};

  # All dashboards as a list
  allDashboards = [
    {name = "master-overview"; dashboard = masterOverview.masterOverview;}
    {name = "deep-insights"; dashboard = deepInsights.deepInsights;}
    {name = "mining"; dashboard = mining.mining;}
    {name = "gpu-monitoring"; dashboard = gpuMonitoring.gpuMonitoring;}
    {name = "ai-inference"; dashboard = aiInference.aiInference;}
  ];

  # Convert dashboard to JSON and create package
  mkDashboard = {name, dashboard}: pkgs:
    pkgs.writeText "${name}.json" (builtins.toJSON dashboard);
in {
  inherit allDashboards masterOverview deepInsights mining gpuMonitoring aiInference;

  # Helper to provision dashboards in Grafana
  provisionDashboards = pkgs: dashboardsDir:
    lib.mapAttrsToList (name: value: ''
      mkdir -p ${dashboardsDir}
      cp ${mkDashboard value pkgs} ${dashboardsDir}/${name}.json
      chown grafana:grafana ${dashboardsDir}/${name}.json
      chmod 644 ${dashboardsDir}/${name}.json
    '') (builtins.listToAttrs (map (d: lib.nameValuePair d.name d) allDashboards));
}
