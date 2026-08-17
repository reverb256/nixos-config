# x86-64-v3 overlay — per-package march=native optimization.
# Each entry overrides a package to compile with AVX2/FMA/BMI2/SSE4.2.
#
# HOLD (already done by nixpkgs or low impact):
#   openssl - AES-NI already used, v3 adds marginal SHA gains
#   openssh - fast enough already
#   jq/fzf/rg - already fast enough
#
# Phased approach: cheap/everywhere first, heavy/specific later.
#
# GUARD: only apply on x86_64 hosts. NixOS applies this overlay to EVERY
# package set, including pkgsi686Linux (32-bit Steam/Wine libs). Forking
# i686 packages with -march=x86-64-v3 makes them non-cacheable and forces a
# from-source i686 rustc/clang bootstrap on the builder (OOM on nexus).
# x86-64-v3 is meaningless on i686 anyway, and aarch64 has its own tuning.
# Vanilla i686 packages stay cacheable from cache.nixos.org (Steam/Wine deps
# are channel blockers upstream).
{ inputs, _final, prev }:

if prev.stdenv.hostPlatform.isx86_64
then {
  # ── Tier 1: cheap, everywhere (tiny builds, broad benefit) ──

  # sqlite: query processing, sorting, hashing, index lookups → AVX2
  sqlite = prev.sqlite.overrideAttrs (old: {
    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE = ((old.env or {}).NIX_CFLAGS_COMPILE or "") + " -O3 -march=x86-64-v3 -DNDEBUG";
    };
  });

  # curl: TLS handshake (SHA-256), HTTP/2 header parsing → AVX2
  curl = prev.curl.overrideAttrs (old: {
    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE = ((old.env or {}).NIX_CFLAGS_COMPILE or "") + " -O3 -march=x86-64-v3 -DNDEBUG";
    };
  });

  # caddy: Go runtime + crypto, TLS edge on your critical path
  caddy = prev.caddy.overrideAttrs (old: {
    GOAMD64 = "v3";
  });

  # pipewire: audio resampling (FMA dot products), mixing, FFT → AVX2
  pipewire = prev.pipewire.overrideAttrs (old: {
    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE = ((old.env or {}).NIX_CFLAGS_COMPILE or "") + " -O3 -march=x86-64-v3 -DNDEBUG";
    };
  });

  # wireplumber: pipewire session manager (profiles, routing, policy)
  wireplumber = prev.wireplumber.overrideAttrs (old: {
    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE = ((old.env or {}).NIX_CFLAGS_COMPILE or "") + " -O3 -march=x86-64-v3 -DNDEBUG";
    };
  });

  # opus: audio codec (Discord, Steam, VoIP) → AVX2 MDCT/LPC/cpldn; low build cost
  opus = prev.opus.overrideAttrs (old: {
    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE = ((old.env or {}).NIX_CFLAGS_COMPILE or "") + " -O3 -march=x86-64-v3 -DNDEBUG";
    };
  });

  # openal-soft: 3D audio framework → AVX2 distance filtering, HRTF convolution; used by games/gamescope
  openal-soft = prev.openal-soft.overrideAttrs (old: {
    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE = ((old.env or {}).NIX_CFLAGS_COMPILE or "") + " -O3 -march=x86-64-v3 -DNDEBUG";
    };
  });

  # ── Tier 2: moderate build, specific workloads ──

  # ffmpeg: every codec is textbook AVX2 — motion estimation (SAD on
  # 32-pixel blocks), DCT, color space conversion (FMA), deblocking, scaling
  ffmpeg = prev.ffmpeg.overrideAttrs (old: {
    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE = ((old.env or {}).NIX_CFLAGS_COMPILE or "") + " -O3 -march=x86-64-v3 -DNDEBUG";
    };
    NIX_CXXFLAGS_COMPILE = ((old.env or {}).NIX_CXXFLAGS_COMPILE or "") + " -march=x86-64-v3";
  });

  # zstd: compression/decompression — xxHash (AVX2 on 64-byte chunks),
  # match finding (BMI2), Huffman. Default nix store compression.
  zstd = prev.zstd.overrideAttrs (old: {
    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE = ((old.env or {}).NIX_CFLAGS_COMPILE or "") + " -O3 -march=x86-64-v3";
    };
  });

  # pixman: 2D rasterizer — composite/blend/scale/fill over 32-byte AVX2
  # pixels. Backing library for cairo, X11, Wayland software fallback.
  pixman = prev.pixman.overrideAttrs (old: {
    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE = ((old.env or {}).NIX_CFLAGS_COMPILE or "") + " -O3 -march=x86-64-v3";
    };
  });

}
else {}

