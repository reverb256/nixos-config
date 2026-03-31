{
  pkgs,
  system ? "x86_64-linux",
  kbMcpSrc ? builtins.fetchGit {
    url = "file:///data/projects/infra/knowledge-base";
    ref = "HEAD";
    # This is a non-git directory, so we use impure path instead
  },
  # Impure path to the pre-downloaded sentence-transformers model cache
  # Model: all-MiniLM-L6-v2 (~88MB) downloaded on the build host
  modelCachePath ? /home/j_kro/.cache/huggingface/hub/models--sentence-transformers--all-MiniLM-L6-v2,
}: let
  # Use impure path for source outside flake
  srcPath = if builtins ? currentSystem then /data/projects/infra/knowledge-base else kbMcpSrc;

  # Copy source into the Nix store (only src directory, pyproject.toml, and scripts)
  kbMcpPkgBase = pkgs.runCommand "kb-mcp-pkg-base" {
    preferLocalBuild = true;
  } ''
    mkdir -p $out/app/kb_mcp/src
    mkdir -p $out/app/kb_mcp/scripts

    # Copy source code
    cp -r ${srcPath}/src/* $out/app/kb_mcp/src/
    cp ${srcPath}/pyproject.toml $out/app/kb_mcp/

    # Copy scripts (ingestion utility)
    cp -r ${srcPath}/scripts/* $out/app/kb_mcp/scripts/

    # Make scripts executable
    chmod +x $out/app/kb_mcp/scripts/*.py 2>/dev/null || true
  '';

  # Pre-cached embedding model baked into the image so the container
  # does not need internet access to download from HuggingFace.
  # Uses -L flag to dereference symlinks so all files are regular copies
  # in the Nix store (avoids permission issues with read-only store paths).
  embeddingModelCache = pkgs.runCommand "embedding-model-cache" {
    preferLocalBuild = true;
  } ''
    mkdir -p $out/hub/models--sentence-transformers--all-MiniLM-L6-v2
    # Copy blobs (regular files, no symlinks)
    cp -r ${modelCachePath}/blobs $out/hub/models--sentence-transformers--all-MiniLM-L6-v2/blobs
    # Copy refs
    cp -r ${modelCachePath}/refs $out/hub/models--sentence-transformers--all-MiniLM-L6-v2/refs
    # Copy .no_exist directory if present (HuggingFace hub metadata)
    cp -r ${modelCachePath}/.no_exist $out/hub/models--sentence-transformers--all-MiniLM-L6-v2/.no_exist 2>/dev/null || true
    # Copy snapshots with dereferenced symlinks (-L) so all files are real copies
    mkdir -p $out/hub/models--sentence-transformers--all-MiniLM-L6-v2/snapshots
    cp -rL ${modelCachePath}/snapshots/* $out/hub/models--sentence-transformers--all-MiniLM-L6-v2/snapshots/
  '';

  # Python environment with all dependencies
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
        # sentence-transformers dependencies
        torch
        transformers
        scikit-learn
        scipy
        tokenizers
        tqdm
        # HTTP server dependencies (fastmcp may need these)
        uvicorn
        starlette
        httpx
        httpcore
        anyio
        sniffio
      ]
  );

  # GCC lib needed for sentence-transformers / torch on NixOS
  gccLib = pkgs.gcc.cc.lib;
  glibc = pkgs.glibc;
in
  pkgs.dockerTools.buildLayeredImage {
    name = "kb-mcp";
    tag = "latest";
    contents = [kbMcpPython kbMcpPkgBase embeddingModelCache pkgs.bash pkgs.coreutils pkgs.cacert gccLib glibc];

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
