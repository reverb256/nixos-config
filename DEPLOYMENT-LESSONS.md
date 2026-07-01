# Deployment Lessons Learned (2026-06-01)

## The Sentry Disaster

### What happened
- Used `nixos-anywhere --flake .#sentry` with disko to deploy NixOS to Sentry
- This is a **provisioning** tool — it formats disks and installs fresh (reads: "never use a production server as the target")
- Should have used **deployment** approach: build closure locally, copy, activate
- Activation failed during nixos-anywhere, leaving Sentry on generation 1 with incomplete activation
- Result: 6-minute boot, 7 failed services, recovery specialisation missing, btrfs UUID stale, wrong niri config

### What we should have done

```bash
# Step 1: Build closure locally
sudo nix build "path:/etc/nixos#nixosConfigurations.<host>.config.system.build.toplevel" --no-link --print-out-paths

# Step 2: Copy to target  
nix copy --to "ssh://j_kro@<ip>" /nix/store/<hash>-nixos-system-<host>-...

# Step 3: Activate (full switch, not boot)
ssh j_kro@<ip> "sudo nix-env -p /nix/var/nix/profiles/system --set /nix/store/<hash>... && sudo /nix/store/<hash>.../bin/switch-to-configuration switch"
```

Never use `switch-to-configuration boot` — it only writes the boot entry without activating services.

### Verification checklist (run after EVERY deployment)
1. `readlink /nix/var/nix/profiles/system` — should be generation > 1
2. `systemctl list-units --state=failed` — should be 0 or known-minor only
3. `sudo bootctl list | grep -c recovery` — should have recovery specialisation
4. `ls /run/agenix/` — should have secrets decrypted
5. `systemd-analyze time` — userspace should be < 1 minute

## Cross-Host Config Contamination

### Problem
Shared modules (`modules/system/home-manager.nix`, `modules/home-manager/niri-config.nix`) had Zephyr-specific configs as defaults for ALL hosts.

### Examples found
- **niri-config.nix**: Zephyr's 4 monitors (DP-4, DP-5, DP-6, HDMI-A-2) were the default. Sentry and Forge silently got them.
- **home-manager.nix**: stylix scheme hardcoded to catppuccin-mocha for ALL hosts, overriding per-host schemes (dracula for Sentry, gruvbox for Forge)

### Rule
Shared modules must use `mkIf (hostName == ...)` for host-specific config, OR pass host-specific values from the host config rather than hardcoding defaults that happen to match Zephyr.

When adding a feature that differs per host (monitors, audio devices, GPU configs, themes):
- Default must be `lib.mkDefault` or generic (e.g., `"*"` for monitor wildcard)
- Per-host overrides via `mkIf (hostName == "...")`
- Test NEW hosts after adding — don't assume Zephyr's config is universal

## Host-Specific Config Pattern

```nix
# Good: universal default, per-host overrides
programs.niri.settings = {
  outputs = {
    "*" = { scale = 1.0; };  # universal default
  };
} // lib.mkIf (hostName == "zephyr") {
  outputs = {
    "DP-5" = { ... };  # Zephyr-specific
    "DP-4" = { ... };
  };
} // lib.mkIf (hostName == "sentry") {
  outputs = {
    "HDMI-A-1" = { ... };  # Sentry-specific
  };
};
```

## Per-Host Monitor Configs (current)

| Host | Monitors | Config |
|------|----------|--------|
| Zephyr | DP-5 (1920x1080@144), DP-4 (1920x1080@75), DP-6 (1600x900@60), HDMI-A-2 (3840x2160@60) | `niri-config.nix` zephyr block |
| Nexus | HDMI-A-1 (3840x2160@60) | `niri-config.nix` nexus block (scale 1.5) |
| Forge | Single 900p | `niri-config.nix` sentry/forge block |
| Sentry | HDMI-A-1 (1600x900@60) | `niri-config.nix` sentry/forge block |

## Deployment Script

A safe deployment script exists at `scripts/deploy-host.sh`:
```bash
./scripts/deploy-host.sh <hostname>     # Deploy to running host
./scripts/deploy-host.sh --rescue <hostname>  # Deploy from USB rescue
```

It:
- Validates the flake target exists
- Never runs disko (does NOT touch disks)
- Builds locally, copies closure, activates with full `switch`
- Verifies host comes up after deployment
