{
  lib,
  pkgs,
  ...
}: let
  # x86-64-v3 tuning for CPU-bound hot paths (2026-08-16).
  #
  # All fleet CPUs are AVX2-capable (zephyr 5950X, nexus 3900X, sentry 1700,
  # forge i5-9500), so -march=x86-64-v3 is safe everywhere. We tune only the
  # packages whose hot loops actually run on the CPU, per-package via
  # overrideAttrs — the rest of nixpkgs stays binary-cache compatible.
  #
  # NOT tuned here (done elsewhere or not worth it):
  #   - llama.cpp: CXXFLAGS live in packages/llama-cpp-turboquant.nix (the
  #     unified fleet binary) — modules/development/llama-cpp-optimization.nix
  #     is DEAD CODE (never imported, targets the wrong llama-cpp attr).
  #   - Lix: per-host -march via lib/lix.nix (znver3/znver2/skylake/znver1).
  #   - Kernel: CachyOS x86-64-v3.
  #   - Whole-nixpkgs hostPlatform.gcc.arch: kills all 10 binary caches for
  #     ~1-5% real-world gain — the Gentoo paradox, not worth it.
  cxxflags = "-march=x86-64-v3";
in {
  nixpkgs.config.packageOverrides = pkgs: {
    # gamescope: CPU-hot compositor (zephyr gaming; also niri-hdr peer).
    gamescope = pkgs.gamescope.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " ${cxxflags}";
    });
    # ffmpeg: media codecs used by comfyui/whisper/recording on nexus + zephyr.
    ffmpeg = pkgs.ffmpeg.overrideAttrs (old: {
      CFLAGS = (old.CFLAGS or "") + " ${cxxflags}";
      CXXFLAGS = (old.CXXFLAGS or "") + " ${cxxflags}";
    });
  };
}
