# Steam Gamescope Session Best Practices

**Purpose:** Reference architecture for a SteamOS-like NixOS session using SDDM, Gamescope, Wayland, and NVIDIA.
**Audience:** Nexus desktop operators and maintainers.
**Last Updated:** 2026-08-11
**Status:** ⚠️ Research complete; implementation changes are not included in this document's research pass.

## Executive Summary

The preferred architecture is the native nixpkgs Steam Gamescope session:

1. Enable `programs.steam` and `programs.steam.gamescopeSession`.
2. Let the nixpkgs Steam module generate the `steam.desktop` session and wrapper.
3. Enable `programs.gamescope` separately when Gamescope options or the WSI layer are needed.
4. Enable 32-bit graphics for broad Steam/Proton compatibility.
5. Use NVIDIA DRM modesetting and the NVIDIA open kernel module on RTX 30-series hardware.
6. Avoid globally forcing Vulkan ICD paths unless a narrowly-scoped diagnostic requires it.
7. Keep the session configuration in one host desktop module; do not duplicate `programs.steam` across host service files and gaming profiles.
8. Treat 4K NVIDIA embedded scanout as a separate compatibility surface. Validate at 1080p/1440p before attributing artifacts to Steam or the miner.

Nexus already uses the native session architecture, but has important contradictions: 32-bit graphics are force-disabled, the Vulkan ICD is globally restricted to one 64-bit JSON file, Gamescope session settings are distributed across multiple files, and the current 4K flags should not be assumed to control an embedded DRM output.

## Primary Sources

- [Official NixOS Steam wiki](https://wiki.nixos.org/wiki/Steam)
- [Official NixOS NVIDIA wiki](https://wiki.nixos.org/wiki/NVIDIA)
- [nixpkgs Steam module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/programs/steam.nix)
- [nixpkgs Gamescope module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/programs/gamescope.nix)
- [Valve Gamescope README](https://github.com/ValveSoftware/gamescope/blob/master/README.md)
- [Valve Gamescope issue #2309: NVIDIA 4K scanout corruption](https://github.com/ValveSoftware/gamescope/issues/2309)
- [Valve Gamescope issue #1964: NVIDIA overlay/artifact behavior](https://github.com/ValveSoftware/gamescope/issues/1964)

These sources are preferred over community snippets because they define the NixOS options, the generated session wrapper, Gamescope semantics, and the upstream failure modes.

## What the Native NixOS Session Actually Does

The nixpkgs `programs.steam.gamescopeSession` option generates a Wayland session file named `steam.desktop` and a `steam-gamescope` wrapper. The wrapper effectively runs:

```bash
gamescope --steam <gamescopeSession.args> -- steam <gamescopeSession.steamArgs>
```

The default Steam arguments in the current nixpkgs module are:

```text
-tenfoot -pipewire-dmabuf
```

This means a native session should not require a custom shell wrapper merely to start Steam in Gamescope. Custom wrappers should be reserved for a demonstrated operational need, such as logging, a carefully scoped environment, or a backend-specific workaround.

The module also:

- enables graphics support;
- enables 32-bit graphics support in the upstream module;
- enables Gamescope by default when the Gamescope session is enabled;
- installs the generated session package into the display manager;
- enables Steam hardware support;
- adds the Steam package and its FHS runtime to the system environment.

Relevant source: [nixpkgs `steam.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/programs/steam.nix).

## Baseline NixOS Configuration

A minimal native session should look conceptually like this:

```nix
{
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  programs.gamescope = {
    enable = true;
    # Enable only when HDR/WSI is required and the package is available.
    enableWsi = true;
    # Enable only when Gamescope needs to renice itself.
    capSysNice = true;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    open = true; # RTX 30-series is supported.
    modesetting.enable = true;
  };
}
```

The exact driver package should remain a deliberate, tested choice. The NVIDIA wiki documents stable, production, beta, and new-feature branches; a driver switch should be an A/B test, not a response to an unverified theory. The module URLs above point to upstream `master` inspected on 2026-08-11; validate option behavior against this flake's pinned nixpkgs revision before implementation.

## NVIDIA RTX 3060 Ti / Ampere Guidance

### Required or strongly recommended

- `services.xserver.videoDrivers = [ "nvidia" ];`
- `hardware.graphics.enable = true;`
- `hardware.nvidia.open = true;` for Turing-and-newer GPUs, including RTX 3060 Ti.
- `hardware.nvidia.modesetting.enable = true;` for Wayland/KMS.
- A recent driver with explicit sync support.
- `hardware.graphics.enable32Bit = true;` for broad Steam, 32-bit native game, and Proton compatibility.

The NVIDIA wiki says open kernel modules are preferred for supported newer GPUs and that modesetting is required for Wayland. The Steam wiki explicitly lists `hardware.graphics.enable32Bit = true` in Steam troubleshooting.

### Avoid broad environment forcing

NVIDIA-specific environment variables should be added only when the actual compositor/driver path requires them. In particular:

- Do not globally force a single 64-bit `VK_ICD_FILENAMES` JSON for a system that runs 32-bit Steam/Proton workloads.
- Prefer normal Vulkan loader discovery first.
- If an ICD override is needed for a diagnostic, scope it to the affected process/session and verify both 64-bit and 32-bit behavior.
- Do not assume `GBM_BACKEND=nvidia-drm` or `__GLX_VENDOR_LIBRARY_NAME=nvidia` fixes a Gamescope DRM scanout bug; they select/assist a backend, but do not repair allocation or page-flip defects.

### 32-bit graphics is strongly recommended for this host

The current shared module contains:

```nix
hardware.graphics.enable32Bit = lib.mkForce false;
```

That conflicts with the Steam wiki's troubleshooting guidance and with the nixpkgs Steam module's own configuration behavior. The local `hardware.nvidia.wayland.enable32Bit` option is currently not wired to `hardware.graphics.enable32Bit`, so its default does not override this setting. This remains a configuration defect even if the native Steam UI happens to start.

The correct long-term fix is to remove the broad force-disable and express any multi-GPU exception at the specific host/profile that actually needs it. Nexus is a dedicated Steam/Proton host and should use the normal 32-bit graphics path.

## Gamescope Flags: Use the Smallest Set

Gamescope's README defines these important distinctions:

- `-W`, `-H`: Gamescope output/window dimensions.
- `-w`, `-h`: client/game rendering dimensions.
- `-r`: client frame-rate limit.
- `-f`: fullscreen window in nested usage.
- `--steam`: Steam-oriented embedded-session behavior.

The README also states that `-W` and `-H` are ignored in embedded mode. Therefore, a native display-manager Steam session must be tested to determine whether it is running embedded DRM/KMS or nested Wayland. Do not assume that adding `-W 3840 -H 2160` changes the physical DRM mode.

Recommended approach:

1. Start with the native session's defaults.
2. Add only the output mode required by the actual backend.
3. Add `--force-composition` only when it measurably improves the target display path.
4. Do not add `--immediate-flips` by default; it changes presentation behavior and is not a general corruption fix.
5. Do not add multiple copies of `--steam`, `--expose-wayland`, or Gamescope flags through both `programs.gamescope.args` and `programs.steam.gamescopeSession.args`.
6. Keep a reproducible diagnostic profile for 1080p/1440p and a separate 4K profile if required.

For Nexus, `--force-composition` should remain a tested operator choice for now, but it should not be treated as a fix for the known 4K NVIDIA scanout issue. Upstream issue [#2309](https://github.com/ValveSoftware/gamescope/issues/2309) reports corruption at 4K with and without `--force-composition`, while 1080p/1440p are clean on the affected systems.

## HDR and Gamescope WSI

The official NixOS Steam wiki says HDR may require:

```nix
programs.gamescope = {
  enable = true;
  enableWsi = true;
};
```

The nixpkgs Gamescope module implements `enableWsi` by adding both `gamescope-wsi` and its 32-bit package to `hardware.graphics.extraPackages` and `extraPackages32`.

This is preferable to manually adding only a 64-bit WSI package to Steam's FHS environment. If HDR is not being tested, avoid enabling extra HDR variables globally; first establish a stable SDR baseline.

## Display Manager and Session Ownership

The session should have one owner for each concern:

| Concern | Recommended owner |
|---|---|
| Steam package and native session | one host desktop module |
| Gamescope package/WSI/capability | shared gaming profile or host desktop module |
| SDDM enablement and Wayland | host desktop module |
| Autologin/default session | host desktop module |
| PeakMiner | host mining module |
| Game workload policy | one explicit host/profile policy |

Nexus currently duplicates `programs.steam` in `hosts/nexus/configuration.nix` and `hosts/nexus/services.nix`, while `gamescopeSession.enable` is also set by the shared gaming module. Although NixOS priorities can make this evaluate successfully, it creates avoidable ownership ambiguity and makes flag changes difficult to audit.

The long-term target is:

- keep `programs.steam` and `programs.gamescope` in `hosts/nexus/desktop.nix` or a dedicated `nexus-steam-session.nix`;
- keep `hosts/nexus/services.nix` for cluster services, not display-session configuration;
- remove redundant `mkForce` usage once the shared module's default is made compatible;
- leave Niri available as an alternate SDDM session, but do not run Niri concurrently with the Steam Gamescope console session.

`services.displayManager.sddm.settings.Autologin.Relogin = true` is appropriate for a console-like recovery path, but it also means a crashing session can be relaunched repeatedly. Crash-loop protection and coredump limits are therefore operational requirements, not optional polish.

## Runtime Health Requirements

A Steam Gamescope session is not healthy merely because `gamescope` has a PID. Acceptance checks should include:

```bash
systemctl --user --failed
coredumpctl list --since '30 minutes ago'
journalctl -b --no-pager | grep -Ei 'gamescope|steam|nvidia|drm|flip|vblank|modifier'
nvidia-smi
cat /proc/pressure/io
```

For Nexus specifically, the current CopyQ restart loop and Gamescope coredumps must be fixed or bounded before graphics tuning can be evaluated reliably. A nearly full Btrfs root and high I/O pressure can make a correct compositor appear broken and can amplify crash handling latency.

Recommended operational safeguards:

- cap coredump storage and retain only a bounded recent set;
- bound journal retention;
- monitor root Btrfs data and metadata headroom;
- avoid running repeated crash-looping user services in an autologin console session;
- test changes after storage pressure returns to normal.

## PeakMiner Coexistence

PeakMiner remains enabled by policy. Ampere can schedule compute and graphics workloads concurrently, so GPU utilization alone is not a sufficient failure diagnosis.

However, the system should make the coexistence policy explicit:

- PeakMiner owns its GPU instance declaratively.
- The Steam session must not silently stop or mutate the miner unless the operator has explicitly selected that policy.
- GameMode should not contain host-specific logic for a different GPU (the shared gaming module currently contains RTX 3090-specific tuning comments/scripts while Nexus has an RTX 3060 Ti).
- Frame-time, GPU power, VRAM, I/O pressure, and Gamescope crash counts should be measured during an A/B comparison, not inferred from utilization alone.

## Recommended Nexus Remediation Order

### Phase 1 — no driver or miner change

1. Fix or disable the CopyQ crash loop in the user session.
2. Bound/vacuum coredumps and reduce excessive journal retention using an intentional, reviewed policy.
3. Restore safe Btrfs headroom, prioritizing obsolete Nix generations and verified disposable caches.
4. Re-test the existing Gamescope session while PeakMiner remains enabled.

### Phase 2 — declarative graphics correctness

5. Remove the broad `hardware.graphics.enable32Bit = lib.mkForce false` policy for Nexus.
6. Stop forcing a single 64-bit `VK_ICD_FILENAMES` globally; validate normal loader discovery and Proton's 32-bit path.
7. Consolidate the duplicated `programs.steam`/Gamescope configuration into the host desktop session owner.
8. Remove stale comments that claim mining is disabled when PeakMiner is enabled.

### Phase 3 — display-path isolation

9. Test native 4K60, 1440p60, and 1080p60 with the same miner and Steam workload.
10. Compare `--force-composition` on/off only after the resolution baseline is known.
11. Record whether the session is embedded DRM/KMS or nested Wayland.
12. If corruption is 4K-only, track it as an upstream Gamescope/NVIDIA scanout issue rather than accumulating local flag workarounds.

### Phase 4 — driver comparison

13. Compare the current driver branch against the repository's stable/production branch using a bootable NixOS generation or specialisation.
14. Keep the branch that passes the acceptance gate: no Gamescope/CopyQ crash loop, clean 4K/1440p output, correct Steam/Proton 32-bit Vulkan, and acceptable frame pacing.
15. Do not change from NVIDIA open modules to proprietary modules without evidence that the open-module path is the specific cause.

## Acceptance Gate

A Nexus Steam session should be considered ready only when all are true:

- SDDM enters the intended `steam` session once.
- `gamescope` stays alive for a sustained test without repeated SIGABRT/SIGSEGV dumps.
- CopyQ is either stable or intentionally disabled.
- `hardware.graphics.enable32Bit` evaluates to `true`.
- 64-bit and 32-bit Vulkan/Proton paths are discoverable.
- No unbounded coredump or journal growth occurs.
- Root Btrfs data and metadata have operational headroom.
- PeakMiner remains active as explicitly intended.
- 1080p/1440p and 4K behavior are recorded separately.
- Any remaining 4K scanout artifact is linked to an upstream issue and not misrepresented as solved by a local flag.

## Current Nexus Findings

| Area | Current state | Assessment |
|---|---|---|
| Native Steam session | Enabled through nixpkgs session | Correct architecture |
| SDDM autologin | Enabled, default `steam`, relogin enabled | Appropriate but can amplify crash loops |
| NVIDIA module | Open module, recent driver, modesetting | Direction is correct |
| 32-bit graphics | Force-disabled by shared module | Incorrect for Steam/Proton |
| Vulkan ICD | Globally forced to 64-bit JSON | Too restrictive; remove or scope |
| Gamescope | 3.16.25, 4K60, force-composition | Needs backend/resolution isolation |
| PeakMiner | Enabled and active | Keep enabled per operator policy |
| CopyQ | Repeated SIGABRT/restarts | Immediate stability blocker |
| Gamescope | SIGABRT/SIGSEGV coredumps observed | Immediate stability blocker |
| Storage | Root 91%; Btrfs data allocation ~97% | Immediate performance risk |

## Public Configuration Examples

The official NixOS/nixpkgs modules are more reliable references than unreviewed personal flakes because they define the option behavior used by this repository. This research pass did not include an independently verified set of five public RTX 3060 Ti-specific flakes; no community example is cited here as authoritative. The upstream NixOS and Valve sources above are the basis for the recommendations.
