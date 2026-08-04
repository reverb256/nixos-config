# Zephyr build cache transport incident

## Symptom

Zephyr toplevel builds on Nexus failed while downloading a large NAR from
`nix-community.cachix.org`:

```text
curl error code=92: HTTP/2 stream ... reset by server
error 0x1: PROTOCOL_ERROR
```

The failing substitute was the CUDA cuBLAS derivation. Downstream failures of
`llama-cpp` and `nixos-system-zephyr` were consequences of that failed NAR
transfer, not NixOS evaluation errors.

## Cause

Nexus was using HTTP/2 with 100 concurrent HTTP connections for large binary
cache transfers. The cache/CDN connection occasionally reset a multiplexed
HTTP/2 stream. Nix retried five times, but the transfer still failed.

## Mitigation

The cluster's distributed-build settings disable HTTP/2, reduce connection
concurrency, and increase retry attempts. The remote-build helper also passes
these settings explicitly and enables `--fallback` so a transient substitute
failure can fall back to building the derivation.

A build is successful only when the top-level Zephyr derivation exits 0 and its
printed store path passes `nix path-info`. Cache-copy progress alone is not a
successful build.
