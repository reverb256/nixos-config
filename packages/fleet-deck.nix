{ lib, buildGoModule, fetchgit }:
# fleet-deck — Charm BubbleTea fleet observability dashboard.
# Built from the reverb256/fleet-deck repo (private). Uses fetchgit so the
# SSH key authenticates (fetchFromGitHub tarball 404s on private repos).
buildGoModule rec {
  pname = "fleet-deck";
  version = "0.1.0";

  src = fetchgit {
    url = "git@github.com:reverb256/fleet-deck.git";
    rev = "b4e59fbefbec3fad14765bb116cc0539b14b8bfe";
    sha256 = "sha256-lkU2OJKFl0HBD5IinO3SVCvY0SYG6w/Sns/xa4Tl4lk=";
  };

  # FIXME(vendor): set after first build on nexus discovers the hash.
  vendorHash = null;

  ldflags = [ "-s" "-w" ];

  meta = with lib; {
    description = "Fleet observability dashboard (BubbleTea TUI)";
    homepage = "https://github.com/reverb256/fleet-deck";
    license = licenses.mit;
    mainProgram = "fleet-deck";
  };
}
