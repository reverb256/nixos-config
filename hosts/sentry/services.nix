# Sentry — GitHub Actions runners (site-agency + nixos-config)
#
# Imported by hosts/sentry/configuration.nix (2026-08-14). Previously this
# file was NOT imported (dead code — configuration.nix held all services
# inline), which is why sentry had NO CI runner and site-agency CI jobs
# queued forever on a non-existent [self-hosted, nixos, gpu] runner.
#
# Sentry runs the site-agency pipeline (its deploy target rsyncs here), so
# the site-agency runner MUST live on this host — not nexus/zephyr.
{
  config,
  lib,
  pkgs,
  ...
}: let
  ciRunners = import ../../modules/services/ci-runners.nix {inherit lib pkgs;};
  runnerFragments = ciRunners {
    instances = {
      nixos-config = {
        user = "runner";
        repo = "reverb256/nixos-config";
        patFile = "/run/secrets/github-runner-pat";
        autoStart = true;
        labels = ["self-hosted" "nixos"];
        extraLabels = ["sentry" "builder"];
        runnerName = "sentry-runner";
        memoryHigh = "8G";
        memoryMax = "12G";
      };
      site-agency = {
        user = "runner";
        repo = "reverb256/site-agency";
        patFile = "/run/secrets/github-runner-pat";
        autoStart = true;
        labels = ["self-hosted" "nixos" "gpu"];
        extraLabels = ["sentry" "site-agency"];
        runnerName = "sentry-site-agency-runner";
        # site-agency CI (lint/security/deploy) is light: venv + ruff +
        # pytest + rsync-to-self. No nix builds. Keep it small.
        memoryHigh = "4G";
        memoryMax = "8G";
      };
    };
  };
in {
  # config = lib.mkMerge so ci-runners' mkMerge fragments compose as a module
  # (the 2026-08-14 fix: plain `runnerFragments //` dropped the fragments).
  config = lib.mkMerge [
    runnerFragments
    {}
  ];
}
