# Build and Deployment Incident Research — 2026-07-31

## Scope

This report investigates the failed attempt to deploy the current NixOS
configuration to Forge and Sentry from Nexus. It combines repository evidence,
the saved Colmena logs on Nexus, and primary-source Nix/Nixpkgs/Colmena
references. Follow-up implementation changed this uncommitted worktree, but no
production activation, deployment, or commit occurred.

The report intentionally separates:

- facts directly demonstrated by the saved logs or repository;
- upstream facts verified from source or official documentation; and
- hypotheses that still require a targeted reproduction.

## Executive summary

The deployment did not complete:

| Host | Recorded version at investigation | Result |
|---|---|---|
| Zephyr | `26.11.20260610.dirty` | Running locally |
| Nexus | `26.11.20260715.753cc8a` | Previously deployed |
| Forge | `26.11.20260715.753cc8a` | New build failed |
| Sentry | `26.05.20260430.15f4ee4` (`usb-rescue`) | New build failed |

The saved logs contain one explicit `builder for ... failed` line per
deployment:

- Sentry: `python3.12-scipy-1.18.0.drv`
- Forge: `libsecret-0.21.7.drv`

These are the only explicit failed-builder leaves recovered from the saved
logs; because the logs were concurrent and progress-output-heavy, they should
not be called proven *first* failures until each derivation is reproduced in
isolation. The large number of later `...dependencies failed to build`
messages are dependency cascades. The log lines previously interpreted as
Mali, Sybase, Intel CET, or general compiler failures are configure/compiler
probes or unrelated package output; they are not sufficient evidence of the
terminal failure.

The strongest repository-level operational finding was builder configuration
drift. The implementation corrected the dormant module's aliases to Nexus
`.120` and Sentry `.140`, while the active `modules/system/distributed-builds.nix`
uses hostname aliases with explicit `HostName` mappings (`nexus` → `.120`,
`sentry` → `.140`). Rendered machine files were evaluated successfully:
Nexus omits itself and lists Sentry via `ssh://`; Sentry lists Nexus via
`ssh-ng://`; both advertise `big-parallel`. The corrected topology is now
validated in source and evaluation, but causality for the original failed
builds remains unproven.

The staged recovery implementation is complete: it uses an explicit daemon
SSH key path, alias-based builder routing, a five-second timeout, a
package-specific libsecret check workaround, and no speculative SciPy override
or global `doCheck` disable. `git diff --check`, `nix flake check --no-build`,
overlay parsing, all four host evaluations, and the active libsecret flag pass.
Deployment remains blocked until Sentry's changed SSH host key is confirmed.

## Evidence collected

### Locked nixpkgs

The flake uses:

```nix
nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
```

The lock file pins:

```text
rev: 0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5
lastModified: 1785318670
```

The upstream GitHub page resolves that SHA to:

> `crackle: fix version (#546473)`

Source: <https://github.com/NixOS/nixpkgs/commit/0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5>

This is important: the SHA itself is not evidence of a Tcl, gettext, SciPy,
or Colmena regression. Earlier reasoning that treated this commit as a known
broad regression was not substantiated by the upstream commit page.

### Exact deployment log leaves

The saved logs on Nexus were timestamped July 31, 2026 and contained:

```text
/tmp/deploy-sentry.log: error: builder for
'/nix/store/s7vq4ana3ilhyi2l21n43r56f2n7p4j0-python3.12-scipy-1.18.0.drv'
failed with exit code 1

/tmp/deploy-forge.log: error: builder for
'/nix/store/cy1z797il3xqnxsz1zr8z01h2irdmi0a-libsecret-0.21.7.drv'
failed with exit code 1
```

The final Colmena messages then reported the target system derivation and
many transitive dependencies as failed. Those are consequences, not
independent root causes.

The SciPy log excerpt available through `nix log` showed substantial build
progress, but the available filtered output did not expose the final failing
command. The libsecret log showed Meson warnings and a DBus `NoReply` message;
the recorded test-collection evidence supports a narrowly scoped workaround,
but the complete terminal command was not captured. The implementation
therefore applies `doCheck = false` only to libsecret as a provisional build
workaround; SciPy remains unchanged and still needs isolated reproduction.

### What the noisy compiler lines mean

The logs contain lines such as:

- `#error Intel CET not available`;
- missing optional EGL headers for Mali/Vivante probes;
- `Compiler for C supports arguments -Werror=...`;
- `checking whether the C compiler works...`.

These are not automatically failures. Autoconf/Meson commonly compiles small
probe programs that are expected to fail while detecting optional capabilities.
A real root cause requires one of:

1. a Nix line stating `error: builder for '<drv>' failed`;
2. the corresponding `nix log <drv>` showing a non-zero build/check/install
   command; or
3. a reproducible isolated build of that exact derivation.

## Upstream package findings

### SciPy 1.18.0

The exact nixpkgs expression at the locked revision defines SciPy 1.18.0 and
sets:

```nix
requiredSystemFeatures = [ "big-parallel" ];
```

It also runs a substantial native test suite on Linux and documents several
known, platform-specific disabled tests. The expression does **not** prove that
this particular Sentry failure is a test failure; it only proves that SciPy is
a resource-sensitive derivation and that builder feature matching is relevant.

Source at the locked revision:
<https://github.com/NixOS/nixpkgs/blob/0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5/pkgs/development/python-modules/scipy/default.nix>

The Nix configuration reference specifies that a machine is selected only
when it advertises every feature in a derivation’s `requiredSystemFeatures`,
and documents the machine-file columns and `builders = @/etc/nix/machines`
form:
<https://nix.dev/manual/nix/stable/command-ref/conf-file>

Official Nix remote-build documentation separately establishes the SSH
requirements and daemon-side identity requirements:
<https://nix.dev/manual/nix/stable/advanced-topics/distributed-builds>

**Conclusion:** verify that the active machine file advertises `big-parallel`
for Nexus and that SciPy was actually scheduled on Nexus (not Sentry, Forge,
or a misresolved alias). Nix’s remote-build documentation describes the
builder requirements and machine configuration; feature matching must also be
verified against the Nix version deployed on the cluster. Do not disable SciPy
tests globally before seeing the isolated failure.

### libsecret 0.21.7

The exact nixpkgs expression defines Linux checks using DBus/GJS and runs
`meson test`. It also contains a test-specific DBus setup. The log’s
`org.freedesktop.DBus.Error.NoReply` line is therefore relevant, but it is not
by itself proof that the build failed because of DBus: the terminal command and
exit status still need to be captured from the full derivation log.

Source at the locked revision:
<https://github.com/NixOS/nixpkgs/blob/0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5/pkgs/by-name/li/libsecret/package.nix>

**Conclusion:** reproduce `libsecret-0.21.7.drv` alone on Nexus and inspect the
first failing Meson test or check command. A narrowly scoped `doCheck = false`
may be justified only if the isolated failure is demonstrably a sandbox-only
DBus test and the package is not relied on for a security-critical test gate.
It should not be used as a blanket fleet-wide workaround.

### Firefox, Plasma, datasets, and optional GPU probes

Firefox, Plasma, Python datasets, Intel CET, Mali/Vivante EGL, and Sybase probe
messages appear in the large logs, but the terminal Nix failure lines point to
SciPy and libsecret. There is currently no evidence in the saved logs that
Firefox, Plasma, or datasets were the first failed derivation.

The repository does import broad module sets for Forge and Sentry. Sentry
explicitly disables Plasma, while Forge imports a desktop module. That may
still create a large closure through shared modules, but this must be measured
with `nix why-depends` or an evaluated closure rather than inferred from log
volume.

## Builder topology audit

### Corrected builder mappings

The cluster inventory is:

```text
nexus = 10.1.1.120
forge = 10.1.1.130
sentry = 10.1.1.140
```

Both the active and dormant builder definitions now use those mappings. The
active source of truth is `modules/system/distributed-builds.nix`, which forces
`nix.settings.builders = "@/etc/nix/machines"`, emits alias-based machine
entries, and installs SSH `HostName` mappings. The dormant
`modules/system/nix-distributed-builders.nix` was corrected as drift cleanup
but is not imported by the active host module set.

The evaluated machine files are:

```text
# Nexus (self omitted)
ssh-ng://j_kro@zephyr x86_64-linux /home/j_kro/.ssh/id_ed25519 0 1
ssh://j_kro@sentry x86_64-linux /home/j_kro/.ssh/id_ed25519 8 6 big-parallel

# Sentry (self omitted)
ssh-ng://j_kro@zephyr x86_64-linux /home/j_kro/.ssh/id_ed25519 0 1
ssh-ng://j_kro@nexus x86_64-linux /home/j_kro/.ssh/id_ed25519 12 10 big-parallel,kvm
```

The machine columns were validated as URL, system, SSH key, max jobs, speed
factor, supported features, and mandatory features. The active topology is
therefore observable and internally consistent. If the dormant module is ever
enabled independently, its `environment.etc."nix/ssh-config-builders"` file is
not automatically consumed by SSH/Nix; it must be explicitly wired into the
active SSH configuration or the module should remain disabled.

### Potentially ambiguous configuration mechanisms

There are two builder mechanisms in the tree:

1. `nix-distributed-builders.nix` declares `nix.builders` directly.
2. `distributed-builds.nix` forces `nix.settings.builders` to
   `@/etc/nix/machines` and generates the machine file.

The active import/evaluation path confirms the second mechanism is the source
of truth. Keeping the dormant module is still a maintenance risk, so it should
remain clearly disabled or be removed in a separate cleanup after deployed-host
imports are rechecked.

## Hostname resolution and dispatcher assumptions

The active machine file uses hostnames such as `nexus` and `sentry`. Nix’s
official remote-build documentation requires that the builder be reachable over
SSH and that the Nix daemon’s SSH identity work non-interactively. A user-shell
SSH test is not sufficient if the Nix daemon runs as root with a different key
or SSH config.

Source: <https://nix.dev/manual/nix/stable/advanced-topics/distributed-builds>

A dispatcher test must therefore verify both:

```bash
sudo ssh -o BatchMode=yes nexus true
sudo nix store ping --store ssh-ng://j_kro@nexus
```

and the same for Sentry, using the exact identity/configure path used by the
Nix daemon.

## Recommended diagnostic sequence

Run these on Nexus, one leaf at a time, before the next full Colmena apply.
These commands are diagnostic and should not modify the target activations.
Building a raw `.drv` store path is supported by current Nix/Lix versions but
should be checked with `nix build --help` on the pinned deployment host; if the
installed version rejects a `.drv` installable, reproduce the corresponding
flake/package attribute instead.

```bash
# Confirm the exact current flake evaluation and host output.
nix eval .#nixosConfigurations.sentry.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.forge.config.system.build.toplevel.drvPath

# Rebuild the exact failed leaves with full logs.
nix build -L --keep-going /nix/store/s7vq4ana3ilhyi2l21n43r56f2n7p4j0-python3.12-scipy-1.18.0.drv
nix log /nix/store/s7vq4ana3ilhyi2l21n43r56f2n7p4j0-python3.12-scipy-1.18.0.drv

nix build -L --keep-going /nix/store/cy1z797il3xqnxsz1zr8z01h2irdmi0a-libsecret-0.21.7.drv
nix log /nix/store/cy1z797il3xqnxsz1zr8z01h2irdmi0a-libsecret-0.21.7.drv

# If direct .drv installables are unsupported by the installed Nix/Lix,
# first resolve the host/package attribute and use that instead, for example:
# nix build -L --keep-going .#nixosConfigurations.sentry.config.system.build.toplevel

# Check what actually pulled heavy packages into a host closure after paths
# are built. Use the exact store paths, not nixpkgs# aliases. Replace each
# angle-bracket placeholder with a real path from `nix path-info`/`nix eval`.
nix why-depends /nix/store/<sentry-system> /nix/store/<scipy>
nix why-depends /nix/store/<forge-system> /nix/store/<libsecret>

# Inspect the active builder file and test the daemon’s SSH path.
cat /etc/nix/machines
sudo ssh -o BatchMode=yes nexus true
sudo ssh -o BatchMode=yes sentry true
sudo nix store ping --store ssh-ng://j_kro@nexus
sudo nix store ping --store ssh://j_kro@sentry
```

Nix’s `nix build` reference documents `--keep-going`, `-L/--print-build-logs`,
`--no-link`, and derivation installables:
<https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-build>

Use `nix log` on the exact failing `.drv`; do not infer the cause from the
system derivation’s dependency cascade.

## Store integrity and remote-builder safety

The previous incident also involved hash mismatches on remote builders. Before
trusting a builder again, verify its store and network path independently:

```bash
# Prefer implicated paths first; whole-store verification is expensive and
# should be scheduled deliberately/off-peak on a large builder. Replace
# <implicated-path> with the actual store path before running this command.
sudo nix store verify --no-trust /nix/store/<implicated-path>
# Whole-store maintenance, only when explicitly scheduled:
# sudo nix store verify --all --no-trust
# Or use the legacy command available on older installations:
# sudo nix-store --verify --check-contents
```

Nix documents `nix store verify` as checking recorded NAR hashes and trust:
<https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-store-verify>

`nix store repair` redownloads a corrupted path from configured substituters,
but Nix warns that interruption can leave a critical path broken:
<https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-store-repair>

Do not run a whole-store repair concurrently with deployment. Verify one
builder, ensure binary caches are reachable, then repair only paths proven
corrupt.

## Prioritized remediation plan

### P0 — Make the active builder topology observable — complete

1. Rendered `nix.settings.builders` and `/etc/nix/machines` for Nexus and Sentry.
2. Confirmed the active source is `distributed-builds.nix`.
3. Corrected the dormant module's `.120`/`.140` drift and normalized daemon key paths.
4. Validated machine columns, alias routing, and `big-parallel` feature tags.
5. Keep exactly one active builder source of truth; leave the legacy module disabled.

### P1 — Reproduce the remaining leaf failure

1. Build the exact SciPy `.drv` independently with `-L`.
2. Capture the first non-zero command and complete test output.
3. Repeat with only Nexus available as a builder and with the active
   `big-parallel` feature advertised.
4. Remove the provisional libsecret override once the upstream/test-environment
   issue is resolved and its check can pass reliably.

### P1 — Protect the recovery host

Sentry is currently `usb-rescue` on the old 26.05 generation. Do not apply a
large new closure there until the leaf failures and target connectivity are
known. A staged `colmena build --on sentry` followed by an explicit closure
transfer/apply may be safer than repeatedly starting full `apply` attempts,
but the exact retention/transfer behavior must be verified against the pinned
Colmena CLI before making it an operational runbook. Do not assume that a
separate `build` automatically creates a durable deployment artifact for a
later `apply`.

Colmena source and documentation:
<https://github.com/zhaofengli/colmena>
<https://colmena.cli.rs/unstable/reference/>

### P2 — Reduce unnecessary closure scope

After the leaf diagnosis, use evaluated dependency paths to determine why
SciPy and libsecret are present. The repository has broad shared imports and a
Forge desktop import; headless or mining-only services should not inherit GUI
and browser packages merely because a shared module imports them. Refactor by
feature gates only after measuring the dependency path.

### P2 — Narrow package workarounds

The current implementation uses a package-specific libsecret override only; it
must be revisited after the isolated check failure is resolved. Do not respond
to this incident by globally setting:

```nix
nixpkgs.config.doCheck = false;
```

or by disabling arbitrary package tests. Such settings hide genuine package
regressions and weaken the signal from system builds. If the isolated leaf log
proves a sandbox-only test failure, add a package-specific override with a
comment containing the exact derivation, upstream issue, and scope.

### P3 — Pin or roll nixpkgs only with evidence

The locked SHA is a valid nixpkgs commit, but its commit subject does not
identify a broad build regression. Compare a candidate revision by building the
two failed leaves and evaluating all four host systems. Do not update the lock
file merely because a full build failed; that makes the incident less
reproducible.

## Research limitations

- The public upstream search did not yield a verified issue specifically tying
  the exact locked SHA to the two recorded leaf failures.
- The saved SciPy and libsecret logs were captured through Colmena and include
  progress-control bytes; their terminal failure summaries identify the `.drv`
  but the filtered excerpts do not yet expose the final failing command.
- The active rendered `/etc/nix/machines` was captured and evaluated; the
  corrected topology is internally consistent.
- No activation, deployment, or commit occurred during this worktree change.
- Strict root SSH and `nix store ping` to Sentry remain blocked by its changed
  host key; the presented ED25519 fingerprint must be confirmed before trust is
  updated.
- The SciPy terminal failure remains unisolated; no SciPy test override was added.

## Sources

1. Nix remote builds: <https://nix.dev/manual/nix/stable/advanced-topics/distributed-builds>
2. Nix build command: <https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-build>
3. Nix store verification: <https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-store-verify>
4. Nix store repair: <https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-store-repair>
5. Locked nixpkgs commit: <https://github.com/NixOS/nixpkgs/commit/0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5>
6. Nix configuration reference (machine syntax and feature matching): <https://nix.dev/manual/nix/stable/command-ref/conf-file>
7. SciPy expression at locked revision: <https://github.com/NixOS/nixpkgs/blob/0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5/pkgs/development/python-modules/scipy/default.nix>
8. libsecret expression at locked revision: <https://github.com/NixOS/nixpkgs/blob/0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5/pkgs/by-name/li/libsecret/package.nix>
9. Colmena repository: <https://github.com/zhaofengli/colmena>
10. Colmena reference: <https://colmena.cli.rs/unstable/reference/>
