# x86-64-v3 overlay — per-package march=native optimization.
# Each entry overrides a package to compile with AVX2/FMA/BMI2/SSE4.2.
# These three packages are the highest-ROI targets on the fleet: data-parallel
# hot loops that auto-vectorize well under v3.
{ inputs, _final, prev }:

{
  # ffmpeg: every codec is textbook AVX2 — motion estimation (SAD on 32-pixel
  # blocks), DCT, color space conversion (FMA pixel math), deblocking, scaling.
  ffmpeg = prev.ffmpeg.overrideAttrs (old: {
    NIX_CFLAGS = "-O3 -march=x86-64-v3 -DNDEBUG";
    NIX_CXXFLAGS = "-march=x86-64-v3";
  });

  # zstd: compression/decompression hot loops — xxHash (AVX2 on 64-byte
  # chunks), match finding (BMI2), Huffman. Default nix store compression.
  zstd = prev.zstd.overrideAttrs (old: {
    CFLAGS = "-O3 -march=x86-64-v3";
  });

  # pixman: 2D rasterizer — composite/blend/scale/fill over 32-byte AVX2 pixels.
  # Backing library for cairo, X11, Wayland software fallback.
  pixman = prev.pixman.overrideAttrs (old: {
    CFLAGS = "-O3 -march=x86-64-v3";
  });
}
