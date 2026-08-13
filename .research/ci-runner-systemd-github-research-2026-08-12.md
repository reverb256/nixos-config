# CI Runner Recovery Research

**Date:** 2026-08-12
**Question:** Is the proposed declarative fix for the offline Nexus GitHub Actions runner safe?

## Conclusion

Do not set the persistent runner setup unit to `RemainAfterExit = false`, and do not register a persistent runner on every service start. Keep the setup unit active after its successful one-shot registration, preserve the runner's persistent `.runner` state, and handle any stale runtime drop-in with a declarative activation-time cleanup that reloads systemd after the drop-in is removed.

## Findings

### systemd oneshot lifecycle

A `Type=oneshot` service with `RemainAfterExit = false` becomes inactive after its command exits. With `RemainAfterExit = true`, it remains `active (exited)` after successful completion. This matters when another unit requires the setup unit to be active.

Sources:

- [systemd.service: RemainAfterExit=](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html#RemainAfterExit=)
- [systemd.unit: Requires=](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html#Requires=)
- [systemd.unit: After=](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html#After=)

`Before=` and `After=` only define ordering. They do not pull a unit into a transaction. `Wants=`/`WantedBy=` create the activation relationship. Therefore, a cleanup unit must have both an activation relationship and ordering if it must run before setup.

### Drop-in removal

When a unit file or drop-in is created, changed, or removed, systemd must reload its unit configuration with `systemctl daemon-reload`. Removing the file alone does not reliably replace the already-loaded unit definition.

Source:

- [systemctl: daemon-reload](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html#daemon-reload)

### GitHub Actions runner registration

GitHub's documented lifecycle is:

1. Add/register the runner with a time-limited registration token.
2. Store the runner application configuration and credentials in the runner directory.
3. Configure the already-added runner as a service.
4. Start and stop the service without re-registering it.

A runner that is only stopped remains assigned on GitHub in an `Offline` state. It can reconnect when the runner application starts again. A runner is removed permanently with the documented removal command, or an inaccessible runner can be force-removed in GitHub. Deleting `.runner` permits re-use of the local application directory for registration, but this is a recovery operation, not a normal boot action.

Sources:

- [Adding self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners)
- [Configuring the self-hosted runner application as a service](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/configure-the-application)
- [Removing self-hosted runners](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/remove-runners)

Registration tokens are short-lived. Re-running registration for a persistent runner on every service start can create a new GitHub runner identity and leave the previous identity offline. Automatic removal rules do not make this a safe normal lifecycle strategy.

## Recommendation for this repository

1. Keep `github-actions-runner-setup.service` as a successful persistent oneshot (`RemainAfterExit = true`) if `github-actions-runner.service` requires it.
2. Do not use `RemainAfterExit = false` as the offline-runner fix.
3. Do not blindly re-run `config.sh` on every runner start.
4. Remove the known stale runtime drop-in declaratively.
5. Run `systemctl daemon-reload` after removing the drop-in, before starting setup.
6. Test the generated unit relationships, cleanup path, reload command, and the persistent setup state. A source-string test alone is weaker than evaluating the generated NixOS service definitions.

## Caveat

The cleanup must not run as a competing dependency in the same start transaction if it changes the definition of the setup unit being started. The safer design is to perform the cleanup and daemon reload during declarative activation, before systemd starts the setup unit, or to make the cleanup a separate explicit activation step with verified ordering.
