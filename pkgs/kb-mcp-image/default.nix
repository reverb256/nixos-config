{
  pkgs,
  system ? "x86_64-linux",
  srcPath ? /data/projects/infra/knowledge-base,
  modelCache ? /home/j_kro/.cache/huggingface/hub/models--sentence-transformers--all-MiniLM-L6-v2,
}:
let
  kbMcpPkgBase =
    pkgs.runCommand "kb-mcp-pkg-base"
    {
      preferLocalBuild = true;
    }
    ''
      mkdir -p $out/app/kb_mcp/src
      mkdir -p $out/app/kb_mcp/scripts
      cp -r ${srcPath}/src/* $out/app/kb_mcp/src/
      cp ${srcPath}/pyproject.toml $out/app/kb_mcp/
      cp -r ${srcPath}/scripts/* $out/app/kb_mcp/scripts/
      chmod +x $out/app/kb_mcp/scripts/*.py 2>/dev/null || true
    '';
  embeddingModelCache =
    pkgs.runCommand "embedding-model-cache"
    {
      preferLocalBuild = true;
    }
    ''
      mkdir -p $out/hub/models--sentence-transformers--all-MiniLM-L6-v2
      cp -r ${modelCache}/blobs $out/hub/models--sentence-transformers--all-MiniLM-L6-v2/blobs
      cp -r ${modelCache}/refs $out/hub/models--sentence-transformers--all-MiniLM-L6-v2/refs
      cp -r ${modelCache}/.no_exist $out/hub/models--sentence-transformers--all-MiniLM-L6-v2/.no_exist 2>/dev/null || true
      mkdir -p $out/hub/models--sentence-transformers--all-MiniLM-L6-v2/snapshots
      cp -rL ${modelCache}/snapshots/* $out/hub/models--sentence-transformers--all-MiniLM-L6-v2/snapshots/
    '';
  kbMcpPython = pkgs.python3.withPackages (
    ps:
      with ps; [
        fastmcp
        qdrant-client
        sentence-transformers
        pydantic
        pydantic-settings
        numpy
        huggingface-hub
        torch
        transformers
        scikit-learn
        scipy
        tokenizers
        tqdm
        uvicorn
        starlette
        httpx
        httpcore
        anyio
        sniffio
      ]
  );
  gccLib = pkgs.gcc.cc.lib;
  glibc = pkgs.glibc;
  realImage = pkgs.dockerTools.buildLayeredImage {
    name = "kb-mcp";
    tag = "latest";
    contents = [
      kbMcpPython
      kbMcpPkgBase
      embeddingModelCache
      pkgs.bash
      pkgs.coreutils
      pkgs.cacert
      gccLib
      glibc
    ];
    config = {
      Cmd = [
        "${kbMcpPython}/bin/python"
        "-m"
        "kb_mcp.server"
      ];
      ExposedPorts = {
        "8080/tcp" = {};
      };
      Env = [
        "PYTHONPATH=/app/kb_mcp/src:/app:${kbMcpPython}/lib/python3.13/site-packages"
        "PATH=${kbMcpPython}/bin:/usr/bin:/bin"
        "LD_LIBRARY_PATH=${gccLib}/lib:${glibc}/lib"
        "QDRANT_HOST=qdrant-service.ai-inference.svc.cluster.local"
        "QDRANT_PORT=6333"
        "KB_PORT=8080"
        "KB_HOST=0.0.0.0"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "REQUESTS_CA_BUNDLE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "HF_HOME=${embeddingModelCache}"
        "TRANSFORMERS_CACHE=${embeddingModelCache}/transformers"
        "HF_HUB_OFFLINE=1"
      ];
      WorkingDir = "/app/kb_mcp";
      Labels = {
        "org.opencontainers.image.title" = "KB MCP Server";
        "org.opencontainers.image.description" = "Knowledge Base RAG MCP Server with vector search over 38 technical eBooks";
      };
    };
  };
in
  pkgs.dockerTools.buildLayeredImage {
    name = "kb-mcp";
    tag = "latest";
    contents = [
      kbMcpPython
      kbMcpPkgBase
      embeddingModelCache
      pkgs.bash
      pkgs.coreutils
      pkgs.cacert
      gccLib
      glibc
    ];
    config = {
      Cmd = [
        "${kbMcpPython}/bin/python"
        "-m"
        "kb_mcp.server"
      ];
      ExposedPorts = {
        "8080/tcp" = {};
      };
      Env = [
        "PYTHONPATH=/app/kb_mcp/src:/app:${kbMcpPython}/lib/python3.13/site-packages"
        "PATH=${kbMcpPython}/bin:/usr/bin:/bin"
        "LD_LIBRARY_PATH=${gccLib}/lib:${glibc}/lib"
        "QDRANT_HOST=qdrant-service.ai-inference.svc.cluster.local"
        "QDRANT_PORT=6333"
        "KB_PORT=8080"
        "KB_HOST=0.0.0.0"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "REQUESTS_CA_BUNDLE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "HF_HOME=${embeddingModelCache}"
        "TRANSFORMERS_CACHE=${embeddingModelCache}/transformers"
        "HF_HUB_OFFLINE=1"
      ];
      WorkingDir = "/app/kb_mcp";
      Labels = {
        "org.opencontainers.image.title" = "KB MCP Server";
        "org.opencontainers.image.description" = "Knowledge Base RAG MCP Server with vector search over 38 technical eBooks";
      };
    };
  }
