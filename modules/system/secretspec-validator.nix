{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.secretspec-validator;

  # Manifest path defaults to the cluster source-of-truth. Per-host overrides
  # via the `manifestPath` option for paths outside /etc/nixos.
  defaultManifest = "/etc/nixos/secretspec.toml";

  profile = if cfg.production then "production" else "default";

  # Auto-couple the validator to the sops-secrets-registry so that any
  # host which has secretspec.toml in scope also validates it. Operators
  # who want to opt out still can — default = registry-coupled.
  defaultEnable = config.services.sops-secrets-registry.enable;
in
{
  options.services.secretspec-validator = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = defaultEnable;
      defaultText = lib.literalExpression "config.services.sops-secrets-registry.enable";
      description = ''
        Whether to run `secretspec check --manifest <manifestPath>
        --profile <profile>` as a systemd one-shot on multi-user.target.

        Defaults to whatever `services.sops-secrets-registry.enable` is set
        to on this host: the validator is meaningful only on hosts that
        have a sops registry to validate against. Set this option
        explicitly to override.

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

    manifestPath = lib.mkOption {
      type = lib.types.str;
      default = defaultManifest;
      description = "Absolute path to the secretspec.toml manifest to validate.";
    };

    failOnMissing = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When true (default), an unresolved required secret causes the
        systemd unit to fail. When false, the unit warns-and-succeeds,
        useful during initial Phase 1 rollout when dotenv values aren't
        yet populated for every secret.
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
    environment.systemPackages = [ pkgs.secretspec ];

    systemd.services.secretspec-validator = {
      description = "SecretSpec schema — validate that every required secret resolves under profile";
      documentation = [ "https://github.com/cachix/secretspec" ];
      wantedBy = [ "multi-user.target" ];

      # secretspec check is fully offline (reads local manifest + dotenv);
      # no network-online.target ordering needed.
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = let
          cmd = "${pkgs.secretspec}/bin/secretspec check"
            + " --manifest ${cfg.manifestPath}"
            + " --profile ${profile}";
          cmd' = if cfg.failOnMissing then cmd
            else cmd + " || true";
        in cmd';
        StandardOutput = "journal";
        StandardError = "journal";
        SuccessExitStatus = if cfg.failOnMissing then "0" else "0 1";
      };
    };

    # Periodic re-check via a separate timer; only registered when
    # onCalendarCheck is non-empty.
    systemd.timers.secretspec-validator = lib.mkIf (cfg.onCalendarCheck != "") {
      description = "Periodic SecretSpec schema drift check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendarCheck;
        Persistent = true;
        Unit = "secretspec-validator.service";
      };
    };
  };
}
