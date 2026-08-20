{ lib, buildGoModule, fetchFromGitHub }:
# fleet-deck — Charm BubbleTea fleet observability dashboard.
# Public repo → fetchFromGitHub (https tarball, sandbox-safe; git@ SSH
# fetch fails inside the Nix sandbox — no ssh binary).
buildGoModule rec {
  pname = "fleet-deck";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "reverb256";
    repo = "fleet-deck";
    rev = "6bcea47";
    hash = "sha256-8eIQHGBGwHcdYmD2AKTVQyNmuVh+CmUc+lzRJAam7Lw=";
  };

  # Vendor hash (discovered via first build).
  vendorHash = "sha256-WyS27hUROWUbP4VtZBuPnsvO2jFOUoJizf7r4oz+2rM=";

  ldflags = [ "-s" "-w" ];

  meta = with lib; {
    description = "Fleet observability dashboard (BubbleTea TUI)";
    homepage = "https://github.com/reverb256/fleet-deck";
    license = licenses.mit;
    mainProgram = "fleet-deck";
  };
}
