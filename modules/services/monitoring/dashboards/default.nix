{lib, ...}: let
  dashboardLib = import ./lib.nix {inherit lib;};

  libExt = lib.extend (_self: _super: {
    dashboard = dashboardLib;
  });

  masterOverview = import ./master-overview.nix {lib = libExt;};
  deepInsights = import ./deep-insights.nix {lib = libExt;};
  mining = import ./mining.nix {lib = libExt;};
  gpuMonitoring = import ./gpu-monitoring.nix {lib = libExt;};
  aiInference = import ./ai-inference.nix {lib = libExt;};

  allDashboards = [
    {
      name = "master-overview";
      dashboard = masterOverview.masterOverview;
    }
    {
      name = "deep-insights";
      dashboard = deepInsights.deepInsights;
    }
    {
      name = "mining";
      dashboard = mining.mining;
    }
    {
      name = "gpu-monitoring";
      dashboard = gpuMonitoring.gpuMonitoring;
    }
    {
      name = "ai-inference";
      dashboard = aiInference.aiInference;
    }
  ];

  mkDashboard = {
    name,
    dashboard,
  }: pkgs:
    pkgs.writeText "${name}.json" (builtins.toJSON dashboard);
in {
  inherit allDashboards masterOverview deepInsights mining gpuMonitoring aiInference;

  provisionDashboards = pkgs: dashboardsDir:
    lib.mapAttrsToList (name: value: ''
      mkdir -p ${dashboardsDir}
      cp ${mkDashboard value pkgs} ${dashboardsDir}/${name}.json
      chown grafana:grafana ${dashboardsDir}/${name}.json
      chmod 644 ${dashboardsDir}/${name}.json
    '') (builtins.listToAttrs (map (d: lib.nameValuePair d.name d) allDashboards));
}
