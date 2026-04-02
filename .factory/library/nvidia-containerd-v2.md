# NVIDIA Container Runtime on containerd v2 - Known Issue

## Problem

On containerd v2 (installed on all cluster nodes via NixOS), the `nvidia-containerd-setup` systemd service generates a config at `/etc/containerd/conf.d/99-nvidia.toml` using `nvidia-ctk runtime configure`. However, the CRI plugin in containerd v2 does NOT recognize the nvidia runtime defined in this drop-in config, causing pods with `runtimeClassName: nvidia` to fail with:

```
Failed to create pod sandbox: unable to get OCI runtime for sandbox: no runtime for "nvidia" is configured
```

## Root Cause

The `nvidia-ctk runtime configure` command uses `containerd config dump` to read the current config (by default). This command performs a partial v2→v3 migration that corrupts the runtime configuration. The CRI plugin then only sees the default `runc` runtime, ignoring the `nvidia` runtime from drop-ins.

See: https://github.com/NVIDIA/nvidia-container-toolkit/issues/1222

## Current State

- `nvidia-container-toolkit` v1.18.2 is installed on all NVIDIA hosts
- The `nvidia-ctk` binary works (version 1.18.2)
- The `nvidia-container-runtime` binary exists at `/nix/store/rz875jd55icq862d08ml0hdkg19j1m9n-nvidia-container-toolkit-1.18.2-tools/bin/nvidia-container-runtime` but is NOT symlinked to `/usr/bin/`
- CDI spec exists at `/var/run/cdi/nvidia-container-toolkit.json` but `nvidia-ctk cdi generate` crashes with SIGSEGV on NixOS
- The `nvidia-containerd-setup` service runs `Before=containerd.service` and regenerates the config on every restart

## Fix (Applied to kubernetes.nix)

Two changes were made to `modules/services/kubernetes.nix` in the `nvidia-containerd-setup` service:

1. **`--config-source=file`**: Forces nvidia-ctk to read config from file instead of using `containerd config dump`
2. **`--nvidia-runtime-path=${pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime`**: Uses the full Nix store path instead of default `/usr/bin/nvidia-container-runtime`

## Additional Issue: Missing runc in PATH

The `nvidia-container-runtime` binary needs `runc` in its PATH but on NixOS, `runc` is only in the containerd service's PATH, not in the system PATH. A wrapper script at `/usr/bin/nvidia-container-runtime` was created on Nexus to work around this, but it won't survive a reboot.

## What's Needed

A full `nixos-rebuild switch` (or `just deploy nexus`) is needed to:
1. Apply the `--config-source=file` and `--nvidia-runtime-path` fixes
2. Potentially also need to create a symlink for `nvidia-container-runtime` in the system PATH
3. Potentially need a wrapper that includes `runc` in PATH

## Verification

After rebuild, verify:
```bash
# Check config was generated correctly
ssh nexus "cat /etc/containerd/conf.d/99-nvidia.toml"

# Check containerd sees the nvidia runtime  
ssh nexus "sudo containerd config dump | grep -A 3 'runtimes.nvidia'"

# Check CRI plugin has nvidia in its config
ssh nexus "sudo journalctl -u containerd --since '10 sec ago' | grep 'starting cri plugin'" | grep nvidia
```

## Workaround (Imperative, until rebuild)

On Nexus, the following was done imperatively (won't survive reboot):
1. Created `/usr/bin/nvidia-container-runtime-wrapper` script that sets PATH with runc and nvidia-container-toolkit bins
2. Created symlink `/usr/bin/nvidia-container-runtime` → `/usr/bin/nvidia-container-runtime-wrapper`
3. Made `/etc/containerd/conf.d/99-nvidia.toml` immutable with `chattr +i` to prevent overwrite

These changes are lost on reboot because:
- The nvidia-containerd-setup service regenerates the config
- The wrapper and symlink are in /usr/bin which is managed by NixOS
