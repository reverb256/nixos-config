# Issue #4: patches/ directory audit + currency check

**Priority:** MEDIUM  \n**Status:** Open  \n**Created:** 2026-07-25  \n**Origin:** Stream 6b of comprehensive plan, compendium item D  \n**Depends on:** none  \n**Blocks:** any future NixOS 26.05 rebuild if stale patches re-enter the build via
`patches = [ ./patches/foo.patch ]` references

## Context

`/etc/nixos/patches/` contains 4 operator-maintained patch files referenced from various
flakes (Plasma widget, Noctalia compositor slice, Niri compositor slice, OpenRazer hid
report header). These are operator-authored diffs for upstream issues that weren't
accepted. The drift-cycle audit (basher run during stream 6b verification) revealed:

| Patch | Target upstream | Apply-test result |
|-------|-----------------|--------------------|
| `patches/openrazer-hid-report-6args.patch` | OpenRazer daemon | Likely OK (function-signature tweak) |
| `patches/hermes-cua-backend-linux.patch` | Hermes CUA backend | **Apply fails** (upstream drift) |
| `patches/noctalia-sdr-brightness.patch` | Noctalia SDR widget | **Apply fails** (upstream drift) |
| `patches/niri-sdr-brightness.patch` | Niri SDR plugin | **Apply fails** (upstream drift) |

If any of these patches is currently wired into a flake-input import (`patches = [
./patches/foo.patch ]` in an overlay), a `nix flake update` will silently fail or build
will silently skip the patched-but-broken logic. **Two patches are referenced verbatim from
either Plasma shell (noctalia) or compositor (niri) — those are load-bearing for daily
operator desktop use.**

The exact references that pull these patches in are NOT clearly mapped. Today `rg -t nix 'patches/' /etc/nixos/{flake.nix,overlay.nix,modules/}` returns hits that need triage.

## Acceptance Criteria

- For each of the 4 patches:
  - Verify which flake-input consumes it (rg audit).
  - Re-test `git apply --check` against the latest upstream source HEAD; capture result.
  - If apply fails, search upstream for the equivalent fix merged in main
    (e.g. `gh pr list -R openrazer/openrazer-meta --search "hid report 6args"`).
  - If apply succeeds, no further action.
  - If upstream fused the fix: archive the patch (`mv patches/foo.patch docs/patches/deprecated/foo.patch`)
    + remove the patch reference from the flake-input.
  - If apply fails AND no upstream fix exists: re-author the patch against current upstream
    and re-version (`patches/foo-2026-07-25.patch`).
- `just patches-audit` recipe added that runs `rg -t nix 'patches/'` + `git apply --check`
  for each patched file and reports staleness.
- `.plans/2026-07-25-patches-audit-results.md` documents outcomes per patch with diff and
  decision (archive / regenerate / unchanged).

## Approach

1. **Inventory**: `rg -t nix 'patches/' /etc/nixos/{flake.nix,overlay.nix,overlay.nix.patch,
   modules/,modules/services/*.nix,hosts/}` — capture every reference.
2. **Apply-test loop**: For each patch, identify the upstream repo (read the `+++`
   filename header), `git clone --depth 1 --branch <branch-or-tag>` to /tmp, `git apply
   --check /etc/nixos/patches/<name>`. Return code 0 = current; non-zero = stale.
3. **Per-patch triage**:
   - **OpenRazer** — check the function-signature of `razer_report` in
     `daemon/openrazer_daemon/hardware/openrazer_report.py` at HEAD. If signature
     changes again, regenerate.
   - **Hermes CUA backend** — `~/Projects/hermes-*/cua-backend/` checkout; apply to latest;
     if upstream Linux-only backend now multi-OS, drop.
   - **Noctalia + Niri SDR** — these target the `brightness` SDR widget which is volatile;
     pin the source commit hash in the flake input + re-author the patch.
4. **Wire the audit into CI** (coordinate with Issue #2 CI gating).
5. **Archive or regenerate**: as appropriate, with `.plans/2026-07-25-patches-audit-results.md`
   recording the decision.

## Risk

- Noctalia / Niri are daily-drive compositors. **Breaking their patch chain causes operator
  desktop regression on next `home-manager switch`**. Mitigate by testing patches in a
  sandboxed `nix shell` first (requires the patch to compile in isolation; if it can't,
  revert).
- If upstream merged the same fix with a different shape, the patched-binary may diverge
  from upstream's binary (`patch` doesn't preserve original-line numbers; `git apply` vs
  `patch -p1` semantics differ).

## Related

- `flake.nix` — flake-input declarations (search for `patches =`)
- `overlay.nix` + `overlay.nix.patch` — overlay patches added on top of nixpkgs
- `modules/desktop/*.nix` — Plasma / Noctalia / Niri module imports
- `patches/openrazer-hid-report-6args.patch` (function-signature tweak)
- `patches/hermes-cua-backend-linux.patch` (Hermes multi-OS fix)
- `patches/noctalia-sdr-brightness.patch` (Plasma widget)
- `patches/niri-sdr-brightness.patch` (Niri compositor)
