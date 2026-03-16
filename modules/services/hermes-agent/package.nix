{ pkgs, lib, config, ... }:
let
  cfg = config.services.hermes-agent;
  python = pkgs.python311;
in
python.pkgs.buildPythonApplication rec {
  pname = "hermes-agent";
  version = "0.1.0-unstable";

  src = config.services.hermes-agent.packageSrc;

  # Enable submodules (mini-swe-agent, tinker-atropos)
  postUnpack = ''
    chmod -R u+w source
    cd source
    git submodule update --init --recursive || true
  '';

  propagatedBuildInputs = with python.pkgs; [
    openai
    python-dotenv
    fire
    httpx
    rich
    tenacity
    pyyaml
    requests
    jinja2
    pydantic
    prompt_toolkit
    firecrawl-py
    fal-client
    edge-tts
    litellm
    typer
    platformdirs
    PyJWT
  ];

  nativeBuildInputs = with pkgs; [
    git
    installShellFiles
  ];

  # Skip tests for now
  doCheck = false;

  meta = with lib; {
    description = "Self-improving AI agent by Nous Research";
    homepage = "https://hermes-agent.nousresearch.com/";
    license = licenses.mit;
  };
}
