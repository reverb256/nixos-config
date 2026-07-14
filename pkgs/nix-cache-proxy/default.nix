{
  lib,
  buildGoModule,
  fetchFromGitHub ? null,
}: let
  # Use the local source (not a GitHub fetch — we're building from the repo)
  src = ../..;
in
  buildGoModule {
    pname = "nix-cache-proxy";
    version = "1.0.0";

    # Use the local source tree; Go module root is pkgs/nix-cache-proxy/
    inherit src;
    modRoot = "pkgs/nix-cache-proxy";
    vendorHash = ""; # No external dependencies — pure stdlib

    # Tell buildGoModule where main.go lives (relative to modRoot)
    subPackages = ["."];

    meta = with lib; {
      description = "Pull-through proxy for Nix binary cache with Prometheus metrics";
      homepage = "https://github.com/reverb256/nixos-config";
      license = licenses.mit;
      mainProgram = "nix-cache-proxy";
      platforms = platforms.linux;
    };
  }
