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
    hash = "sha256-6W6z8/NOSe07lTmpoWiwaERkmVsMCeI6jyDAoqPFBcs=";
  };
  format = "pyproject";
  buildInputs = (old.buildInputs or []) ++ [python3Packages.setuptools];
})
