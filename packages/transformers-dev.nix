{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.transformers.overrideAttrs (old: rec {
  version = "5.6.0-dev";
  src = fetchFromGitHub {
    owner = "huggingface";
    repo = "transformers";
    rev = "c472755e79aac54d675845bff5e5c821c21260af";
    hash = "sha256-1jq5qnis5h10iwxf428cbfcn8i38n1la3a9rjlxysjafygrv6vp9";
  };
  format = "pyproject";
  buildInputs = (old.buildInputs or []) ++ [ python3Packages.setuptools ];
})
