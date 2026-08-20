# Sentry — GitHub Actions runners (BUILD MUSCLE)
#
# Concern-based split (2026-08-19): nexus owns deploy authority + HM; sentry
# owns build-heavy runners (lix, quill) + site-agency. The duplicate
# nixos-config runner that previously lived here (competing with nexus's
# nexus-runner) is REMOVED — deploy authority stays single-source on nexus.
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
      site-agency = {
        user = "runner-siteagency";
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
      lix = {
        user = "runner-lix";
        repo = "reverb256/lix";
        patFile = "/run/secrets/github-runner-pat";
        autoStart = true;
        labels = [ "self-hosted" "nixos" ];
        extraLabels = [ "sentry" "builder" ];
        runnerName = "sentry-lix-runner";
        # Lix CI delegates the heavy build to the nix daemon (not the runner
        # cgroup), so the listener needs little RAM. Capped for sentry's 31GiB.
        #
        # disableNoNewPrivileges: the lix test suite runs nix sandboxed
        # (unshare CLONE_NEWUSER | CLONE_NEWNS). NoNewPrivileges=true blocks
        # that even when kernel.unprivileged_userns_clone=1. The old GitHub-
        # hosted workflow got root via sudo; the self-hosted runner runs as
        # runner-lix, so we must allow user namespaces for sandboxing to work.
        disableNoNewPrivileges = true;
        memoryHigh = "6G";
        memoryMax = "10G";
      };
      quill = {
        user = "runner-quill";
        repo = "reverb256/quill";
        patFile = "/run/secrets/github-runner-pat";
        autoStart = true;
        labels = ["self-hosted" "nixos"];
        extraLabels = ["sentry" "quill"];
        runnerName = "sentry-quill-runner";
        # Quill CI is venv + ruff + pytest + rsync; build delegated to nix
        # daemon. Capped for sentry's 31GiB alongside site-agency + lix.
        memoryHigh = "6G";
        memoryMax = "10G";
      };
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
