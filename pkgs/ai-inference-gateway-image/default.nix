{
  pkgs,
  system ? "x86_64-linux",
}: let
  # Gateway source code
  gatewaySrc = /etc/nixos/modules/services/ai-inference/ai_inference_gateway;

  # Gateway source package
  gatewayPkgBase = pkgs.runCommand "ai-inference-gateway-pkg-base" {
    preferLocalBuild = true;
  } ''
    mkdir -p $out/app
    cp -r ${gatewaySrc}/* $out/app/
    chmod +x $out/app/main.py
  '';

  # Python environment with all dependencies
  gatewayPython = pkgs.python3.withPackages (
    ps:
      with ps; [
        fastapi
        uvicorn
        httpx
        prometheus-client
        pyjwt
        cryptography
        python-multipart
        uvloop
        httptools
        qdrant-client
        sentence-transformers
        rank-bm25
        numpy
      ]
  );
in
  pkgs.dockerTools.buildLayeredImage {
    name = "ai-inference-gateway";
    tag = "local";
    contents = [gatewayPython gatewayPkgBase];
    config = {
      Cmd = [
        "uvicorn"
        "ai_inference_gateway.main:app"
        "--host"
        "0.0.0.0"
        "--port"
        "8080"
        "--workers"
        "4"
      ];
      ExposedPorts = {
        "8080/tcp" = {};
      };
      Env = [
        "PYTHONPATH=/app"
        "PATH=/usr/bin:/bin"
      ];
      WorkingDir = "/app";
      Labels = {
        "org.opencontainers.image.title" = "AI Inference Gateway";
        "org.opencontainers.image.description" = "OpenAI-compatible API gateway with RAG and MCP support";
      };
    };
  }
