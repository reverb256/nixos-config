# User Testing Surface

## Validation Surface

This mission has no browser or API surface. All validation is via:
- `nix flake check` (NixOS config syntax validation, catches option errors)
- `bash -n` (shell script syntax validation)
- `grep` (structural assertions on file content)

No user-facing application to test. No agent-browser needed.

## Validation Concurrency

N/A - no concurrent validators needed. Single `nix flake check` validates all 4 hosts.

## Resource Cost

`nix flake check` is lightweight:
- Runs locally on Zephyr (31GB RAM, 32 cores)
- Takes <5 seconds
- No network required (uses local nix store)
- No services started
