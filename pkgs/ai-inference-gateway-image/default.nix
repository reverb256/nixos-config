{
  pkgs,
  system ? "x86_64-linux",
}: let
  # Gateway source code (relative to flake root)
  gatewaySrc = ./../../modules/services/ai-inference/ai_inference_gateway;
  # Gateway source package
  gatewayPkgBase =
    pkgs.runCommand "ai-inference-gateway-pkg-base" {
      preferLocalBuild = true;
    } ''
      mkdir -p $out/app/ai_inference_gateway
      cp -r ${gatewaySrc}/* $out/app/ai_inference_gateway/
      chmod +x $out/app/ai_inference_gateway/main.py
    '';
  # Python environment with all dependencies
  gatewayPython = pkgs.python3.withPackages (
    ps:
      with ps; [
        fastapi
        uvicorn
        httpx
        openai
        anthropic
        prometheus-client
        pyjwt
        cryptography
        python-multipart
        uvloop
        httptools
        aiohttp
        psutil
        qdrant-client
        sentence-transformers
        rank-bm25
        numpy
        beautifulsoup4
        redis
        pydantic
        pydantic-settings
        sentry-sdk
        mcp
        huggingface-hub
      ]
  );
in
  pkgs.dockerTools.buildLayeredImage {
    name = "ai-inference-gateway";
    tag = "local";
    contents = [gatewayPython gatewayPkgBase pkgs.bash pkgs.coreutils];
    config = {
      Cmd = [
        "${gatewayPython}/bin/python"
        "-m"
        "uvicorn"
        "ai_inference_gateway.main:app"
        "--host"
        "0.0.0.0"
        "--port"
        "8080"
      ];
      ExposedPorts = {
        "8080/tcp" = {};
      };
      Env = [
        "PYTHONPATH=/app/ai_inference_gateway:/app:${gatewayPython}/lib/python3.13/site-packages"
        "PATH=${gatewayPython}/bin:/usr/bin:/bin"
      ];
      WorkingDir = "/app/ai_inference_gateway";
      Labels = {
        "org.opencontainers.image.title" = "AI Inference Gateway";
        "org.opencontainers.image.description" = "OpenAI-compatible API gateway with RAG and MCP support";
      };
    };
  }
