{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.secretspec-validator;

  # Manifest path defaults to the cluster source-of-truth. Per-host overrides
  # via the `manifestPath` option for paths outside /etc/nixos.
  defaultManifest = "/etc/nixos/secretspec.toml";

  profile =
    if cfg.production
    then "production"
    else "default";

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
      after = ["secretspec-creds.service"];
      wants = ["secretspec-creds.service"];

      # secretspec check is fully offline (reads local manifest + dotenv);
      # no network-online.target ordering needed.
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = let
          cmd =
            "${pkgs.secretspec}/bin/secretspec check"
            + " --file ${cfg.manifestPath}"
            + " --profile ${profile}";
          cmd' =
            if cfg.failOnMissing
            then cmd
            else cmd + " || true";
        in
          cmd';
        # Wire the sops:// subprocess dispatcher into the secretspec binary
        # so `providers = ["sops"]` chains resolve via NDJSON over stdio.
        # Without this env var, `secretspec check` falls back to env/dotenv
        # providers only and the validator reports every sops-routed
        # secret as unresolved.
        # SOPS_AGE_KEY_FILE must be set in addition so the sops:// subprocess
        # itself can decrypt the configured YAML/binary key file; without it,
        # the validator would find the file (provider binary is reachable)
        # but the subprocess would refuse with "no key could be found".
        Environment = [
          "SOPS_AGE_KEY_FILE=${cfg.ageKeyFile}"
          "SECRETSPEC_SOPS_PROVIDER_BIN=${pkgs.secretspec-provider-sops}/bin/secretspec-provider-sops-protocol"
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
