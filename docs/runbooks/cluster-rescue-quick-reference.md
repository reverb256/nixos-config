# Cluster Rescue Quick Reference

Use the full [NixOS USB-Rescue Runbook](./nixos-usb-rescue.md) for the procedure and safety rules. The older `scripts/rescue/RESCUE-GUIDE.md` and `RESCUE-AGENT.md` files are compatibility pointers, not separate procedures.

## Read-only first

```bash
HOST=sentry                         # zephyr | nexus | forge | sentry
TARGET=/mnt/$HOST-root
KH=$HOME/.ssh/known_hosts-$HOST-rescue

sudo scripts/rescue/rescue-cli.sh discover --host "$HOST"
sudo scripts/rescue/rescue-cli.sh mount --host "$HOST" --target-root "$TARGET"
sudo scripts/rescue/rescue-cli.sh diagnose --host "$HOST" --target-root "$TARGET"
```

## Mutating phases require two gates

Every mutating command must include both:

```text
--apply --confirm-target
```

Mount:

```bash
sudo scripts/rescue/rescue-cli.sh mount \
  --host "$HOST" --target-root "$TARGET" \
  --apply --confirm-target
```

Transfer:

```bash
sudo scripts/rescue/rescue-cli.sh transfer \
  --host "$HOST" \
  --closure /nix/store/<hash>-nixos-system-$HOST-... \
  --target-root "$TARGET" \
  --known-hosts "$KH" \
  --apply --confirm-target
```

Prepare boot:

```bash
sudo scripts/rescue/rescue-cli.sh prepare-boot \
  --host "$HOST" \
  --closure /nix/store/<hash>-nixos-system-$HOST-... \
  --target-root "$TARGET" \
  --known-hosts "$KH" \
  --apply --confirm-target
```

Pre-reboot verification:

```bash
sudo scripts/rescue/rescue-cli.sh verify \
  --host "$HOST" --mode pre \
  --closure /nix/store/<hash>-nixos-system-$HOST-... \
  --target-root "$TARGET"
```

Unmount and reboot:

```bash
sudo scripts/rescue/rescue-cli.sh unmount \
  --host "$HOST" --target-root "$TARGET"
sudo scripts/rescue/rescue-cli.sh unmount \
  --host "$HOST" --target-root "$TARGET" \
  --apply --confirm-target
sync
sudo reboot
```

Post-boot:

```bash
scripts/rescue/rescue-cli.sh verify \
  --host "$HOST" --mode post \
  --known-hosts "$HOME/.ssh/known_hosts"
```

## Builder/dispatcher rule

Build the target toplevel on the designated builder/dispatcher (currently
Nexus). The rescue environment is only for discovery, mounting, diagnosis,
transfer, and target boot preparation. A build-start line is not evidence of
success: require exit status zero, a verified `/nix/store/...-nixos-system-*`
toplevel, closure metadata, and target-store verification.

## Hard stops

Stop if discovery does not match the host profile, the rescue fingerprint is
not console-verified, the target Nix store is not mounted, the build did not
exit zero, the target profile does not resolve to the verified toplevel, or
any required boot artifact is missing.

Never run formatting/provisioning tools, delete generations, garbage-collect,
accept a changed SSH key blindly, or import into the rescue `/nix/store`.
