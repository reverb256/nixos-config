# Upstream Binary-Cache Policy

**Issue:** #415
**Last verified:** 2026-08-07

## Objective

The target is reuse of the exact derivations published by upstream builders:

- Hydra / `cache.nixos.org`;
- `cache.nixos-cuda.org` for CUDA-enabled packages where coverage exists;
- `nix-community.cachix.org` and other declared project Cachix caches;
- declared ROCm/project caches when exact coverage exists.

The local `reverb-os.cachix.org` and Zephyr cache are fallback caches for
intentional custom artifacts. Their presence must not hide an accidental
upstream derivation miss.

A cache hit requires the exact output path. The same package name and version
are insufficient when nixpkgs revision, build flags, dependencies, Python scope,
CUDA/ROCm versions, patches, or compiler inputs differ.

## Policy classes

Important derivations belong to one of these classes:

| Class | Meaning |
|---|---|
| `upstream-required` | Must preserve the upstream derivation identity whenever the relevant cache provides it. |
| `specialized-cache-expected` | Expected to use a named CUDA, Nix Community, Niri, Noctalia, gaming, or other project cache when that cache covers the exact derivation. |
| `intentional-custom` | Deliberately differs from upstream and may be built/published through `reverb-os`. |

The initial explicit custom list lives in `contracts/cache-policy.nix`. It
includes the custom Niri HDR package, local llama.cpp CUDA/ROCm/Vulkan variants,
Python packages with local source/build changes, and patched system packages.
This list is a classification baseline, not permission to add global overrides.

## Cache configuration

`contracts/cache-policy.nix` is the canonical source for substituters and trusted
keys. `modules/system/nix-config.nix` and
`modules/system/distributed-builds.nix` consume it. Public upstream and
specialized caches have higher priority than the local caches.

Adding a cache URL does not prove package coverage. Third-party cache keys grant
that cache authority to provide executable store paths and must be reviewed as
supply-chain trust decisions.

## Audit workflow

Offline/static policy checks run through:

```bash
nix flake check --no-build
```

The network-dependent audit is separate:

```bash
just cache-audit
```

It evaluates each host toplevel derivation, samples relevant derivation
outputs, and probes cache `narinfo` endpoints. It does not build or substitute.
A `METADATA HIT` means the cache advertises the store hash; it is not a
signature-verification result. Actual Nix substitutions still require valid
signatures because `require-sigs = true`. A miss is reported for classification;
custom outputs are expected to miss upstream caches. The current audit samples
build-time derivation graph outputs, not a realized runtime closure; a future
post-build audit can use `nix path-info --recursive` on the realized system.


## Follow-up implementation

The next phases should move global package mutations to leaf-level consumers:

1. remove global replacement of standard `llama-cpp`;
2. isolate CUDA/ROCm custom variants with explicit package names/arguments;
3. scope Python overrides to the AI environment that requires them;
4. migrate standalone Home Manager instantiation to root-owned canonical package
   policy and use the shared package set for integrated HM;
5. extend the provenance manifest from the initial custom baseline to all
   protected derivations and make undeclared upstream divergence fail the audit.
