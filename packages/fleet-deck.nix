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
    rev = "5f4c0cc06ed630552ed6078f9676bf92b7deac7e";
    hash = "sha256-8ag0ggf6Mqxc+UEuht4eq5Wha7OCnajauaE3oYd8CY0=";
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
