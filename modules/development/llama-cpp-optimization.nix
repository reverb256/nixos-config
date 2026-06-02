{
  config,
  lib,
  pkgs,
  ...
}: let
  hostName = config.networking.hostName or null;
  llHosts = ["sentry" "forge" "zephyr"];
in
  lib.mkIf (hostName != null && builtins.elem hostName llHosts) (let
    tune =
      {
        sentry = "haswell";
        forge = null;
        zephyr = "zen3";
      }.${
        hostName
      };
    mtune = lib.optionalString (tune != null) " -mtune=${tune}";
    cxxflags = "-march=x86-64-v3${mtune}";
    hasVulkan = builtins.elem hostName ["sentry" "forge"];
  in {
    nixpkgs.config.packageOverrides = pkgs:
      {
        llama-cpp-turboquant = pkgs.llama-cpp-turboquant.overrideAttrs (old: {
          CXXFLAGS = (old.CXXFLAGS or "") + " ${cxxflags}";
        });
        llama-cpp = pkgs.llama-cpp.overrideAttrs (old: {
          CXXFLAGS = (old.CXXFLAGS or "") + " ${cxxflags}";
        });
      }
      // lib.optionalAttrs hasVulkan {
        llama-cpp-vulkan = pkgs.llama-cpp-vulkan.overrideAttrs (old: {
          CXXFLAGS = (old.CXXFLAGS or "") + " ${cxxflags}";
        });
      };
  })
