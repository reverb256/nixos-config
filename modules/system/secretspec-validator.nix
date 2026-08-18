# ============================================================================
# SECRETSPEC VALIDATOR
# ============================================================================
# Runtime schema validation of /etc/nixos/secretspec.toml (`secretspec check`)
# as a systemd one-shot on multi-user.target, decrypted against the age key.
#
# EVAL-MODE (2026-08-14): the global `nix.settings.pure-eval = true`
# (added 2026-08-13 with `eval-cache = true`) was REVERTED in
# modules/system/nix-config.nix — it broke home-manager switch (the news
# step's NIX_PATH `<home-manager/...>` lookup fails in pure mode). This
# module never touches the eval path — secrets are decrypted at runtime
# by secretspec-creds into /run/secrets, and the validator only reads those
# runtime paths. `cluster.localSealSupport` was removed 2026-07-25 (vestigial
# after Phase 1a; see modules/system/secretspec-cluster-mode.nix).
# ============================================================================
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.services.secretspec-validator;

  # Manifest path defaults to the cluster source-of-truth. Per-host overrides
  # via the `manifestPath` option for paths outside /etc/nixos.
  #
  # The manifest's sops:// URIs point at /etc/nixos/secrets/ — but secrets
  # now live in the private nixos-secrets flake's store path. Generate a
  # store-level copy with the path interpolated so `secretspec check`
  # resolves the sops:// URIs against the private flake's secrets directory.
  secretspecSource = builtins.readFile ./../../secretspec.toml;
  secretspecManifest = pkgs.writeText "secretspec.toml" (
    # Replace '/etc/nixos/secrets/' with the private flake's store path
    # so sops:/// URIs resolve against the nix store copy of the secrets.
    lib.strings.replaceStrings
      ["/etc/nixos/secrets/"]
      ["${inputs.nixos-secrets}/secrets/"]
      secretspecSource
  );
  defaultManifest = secretspecManifest;

  profile =
    if cfg.production
    then "production"
    else "default";

  validatorScript = pkgs.writeShellScript "secretspec-validator" ''
    set -o errexit
    set -o nounset
    set -o pipefail

    if ${pkgs.secretspec}/bin/secretspec check \
      -f ${cfg.manifestPath} \
      -P ${profile}
    then
      exit 0
    else
      status=$?
    fi

    ${lib.optionalString (!cfg.failOnMissing) ''
      # Non-blocking mode records validation failures without making
      # activation fail; systemd still logs the validator output.
      exit 0
    ''}

    exit "$status"
  '';
in {
  options.services.secretspec-validator = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to run `secretspec check --file <manifestPath>
        --profile <profile>` as a systemd one-shot on multi-user.target.

        Default is `false` (Phase 1a/1b, 2026-07-25): the validator is
        now opt-in per host. Hosts that wish to enforce SecretSpec schema
        validation at activation must set this option explicitly in
        hosts/<host>/services.nix.

        On failure the unit stays failed and blocks downstream services
        whose units declare `After=secretspec-validator.service`. This is
        the intended fail-loud behavior — silent resolution drift is the
        leading cause of "service started but config was wrong" outages.
      '';
    };

    production = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When true, validates the `production` profile (every required
        secret must resolve). When false, validates the `default` profile
        (developer mode — only requires secrets marked required in [profiles.default]).
      '';
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/.age/key.txt";
      description = ''
        Path to the SOPS-compatible age keyfile passed to the validator.
        Defaults to the same path as <option>services.secretspec-creds.ageKeyFile</option>.
        The two options share a default literally rather than referencing
        each other so a host can enable the validator without also enabling
        (or even importing) the resolver module — keeps the options tree
        independent of import order.
        Override only when the validator needs a different identity than
        the resolver (e.g. a read-only key on a CI runner).
        Note: rotating only `services.secretspec-creds.ageKeyFile` without
        also updating this option leaves the validator decrypting with the
        stale key; rotate BOTH on every credential rotation.
      '';
    };

    manifestPath = lib.mkOption {
      type = lib.types.str;
      default = defaultManifest;
      description = "Absolute path to the secretspec.toml manifest to validate.";
    };

    failOnMissing = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true, an unresolved required secret causes the systemd unit
        to fail. When false (default), the unit warns-and-succeeds.

        See modules/system/SECRETSPEC-CONSOLIDATION.md for the rationale
        behind the cluster default of false (was true prior to the 2026-07-25
        Phase-2 consolidation; flipped because the validator logs were
        drowning nexus + forge journals even when every actually-required
        secret was provisioned).
      '';
    };

    onCalendarCheck = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      example = "weekly";
      description = ''
        systemd OnCalendar spec for periodic re-validation. Default is
        `daily`; set to `weekly` or `monthly` to reduce journald noise.
        Set to "" to disable periodic checks (only run on activation).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.secretspec];

    systemd.services.secretspec-validator = {
      description = "SecretSpec schema — validate that every required secret resolves under profile";
      documentation = ["https://github.com/cachix/secretspec"];
      wantedBy = ["multi-user.target"];

      # Ordering chain: secretspec-creds populates /run/secrets/* with
      # decrypted SOPS values, then the validator walks /etc/nixos/secretspec.toml
      # against those paths + the dotenv fallback. Without this ordering, a
      # fresh-host boot failed the validator every time and the journal
      # produced a cascade of "Failed to start SecretSpec schema" entries
      # until the next reboot (was previously the loudest log noise on
      # nexus + forge). `Wants` (not `Requires`) means creds starting will
      # still trigger this unit; a creds failure will be reported on its own
      # unit, not here. See modules/system/SECRETSPEC-CONSOLIDATION.md.
      # Wait for the on-disk age key: it lives at /etc/nixos/.age/key.txt
      # which is bound from /persistent by the preservation module's
      # etc-nixos-.age.mount unit. Without this ordering a fresh boot can
      # race the validator ahead of the bind and the keyfile is momentarily
      # absent. (boot-race fix 2026-08-10)
      after = ["secretspec-creds.service" "etc-nixos-.age.mount"];
      wants = ["secretspec-creds.service" "etc-nixos-.age.mount"];

      # secretspec check is fully offline (reads local manifest + dotenv);
      # no network-online.target ordering needed.
      #
      # PATH must carry the sops CLI: the upstream secretspec sops provider
      # (0.18.0) shells out to `sops` to decrypt YAML. Without this, systemd's
      # default unit PATH omits it, `secretspec check` errors "sops not found",
      # the unit fails, and every subsequent `nixos-rebuild switch` aborts
      # during activation. age is included for the age-backed identity path.
      path = [
        pkgs.sops
        pkgs.age
        pkgs.coreutils
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = validatorScript;
        # SOPS_AGE_KEY_FILE must be set so the upstream sops provider
        # (0.18.0) can decrypt the sops:// aliases directly via the sops CLI.
        # The reverb256 fork (SECRETSPEC_SOPS_PROVIDER_BIN protocol dispatcher)
        # was deleted 2026-08-07; upstream native provider subsumed it.
        Environment = [
          "SOPS_AGE_KEY_FILE=${cfg.ageKeyFile}"
          # The `age` crate sops shells out to refuses SOPS_AGE_KEY_FILE
          # unless $HOME is defined (errors "$HOME is not defined. Did not
          # find keys in ... SOPS_AGE_KEY_FILE"). Without this the validator
          # fails at activation even when the keyfile is present. (root
          # cause 2026-08-10)
          "HOME=/root"
        ];
        StandardOutput = "journal";
        StandardError = "journal";
        SuccessExitStatus =
          if cfg.failOnMissing
          then "0"
          else "0 1";
      };
    };

    # Periodic re-check via a separate timer; only registered when
    # onCalendarCheck is non-empty.
    systemd.timers.secretspec-validator = lib.mkIf (cfg.onCalendarCheck != "") {
      description = "Periodic SecretSpec schema drift check";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.onCalendarCheck;
        Persistent = true;
        Unit = "secretspec-validator.service";
      };
    };
  };
}
