{
  pkgs,
  system ? "x86_64-linux",
  srcPath ? /data/projects/knowledge-fabric/backend,
  modelCache ? /home/j_kro/.cache/huggingface/hub/models--nomic-ai--nomic-embed-text-v2-moe,
}:
let
  kfPkgBase =
    pkgs.runCommand "knowledge-fabric-pkg-base"
      { preferLocalBuild = true; }
      ''
        mkdir -p $out/app
        cp -r ${srcPath}/app/* $out/app/
        chmod -R u+w $out
      '';

  embeddingModelCache =
    pkgs.runCommand "nomic-embed-model-cache"
      { preferLocalBuild = true; }
      ''
        mkdir -p $out/hub/models--nomic-ai--nomic-embed-text-v2-moe
        cp -r ${modelCache}/blobs $out/hub/models--nomic-ai--nomic-embed-text-v2-moe/blobs
        cp -r ${modelCache}/refs $out/hub/models--nomic-ai--nomic-embed-text-v2-moe/refs
        cp -rL ${modelCache}/snapshots $out/hub/models--nomic-ai--nomic-embed-text-v2-moe/snapshots
      '';

  kfPython = pkgs.python313.withPackages (
    ps:
    with ps; [
      # Web framework
      fastapi
      uvicorn
      pydantic
      pydantic-settings
      python-multipart
      sse-starlette
      starlette

      # HTTP
      httpx

      # Vector DB
      qdrant-client

      # Embeddings + ML
      sentence-transformers
      torch
      transformers
      numpy
      scikit-learn
      scipy
      tokenizers
      huggingface-hub

      # Page fetching
      readability-lxml
      beautifulsoup4
      lxml

      # Utilities
      anyio
      sniffio
      tqdm
    ]
  );

  gccLib = pkgs.gcc.cc.lib;
  glibc = pkgs.glibc;
  zlib = pkgs.zlib;
in
pkgs.dockerTools.buildLayeredImage {
  name = "knowledge-fabric";
  tag = "latest";
  contents = [
    kfPython
    kfPkgBase
    embeddingModelCache
    pkgs.bash
    pkgs.coreutils
    pkgs.cacert
    gccLib
    glibc
    zlib
  ];

  config = {
    Cmd = [
      "${kfPython}/bin/python"
      "-m"
      "uvicorn"
      "app.main:app"
      "--host"
      "0.0.0.0"
      "--port"
      "8100"
    ];
    ExposedPorts = {
      "8100/tcp" = { };
    };
    Env = [
      "PYTHONPATH=/app:${kfPython}/lib/python3.13/site-packages"
      "PATH=${kfPython}/bin:/usr/bin:/bin"
      "LD_LIBRARY_PATH=${gccLib}/lib:${glibc}/lib:${zlib}/lib"
      "KF_QDRANT_URL=http://qdrant-service.ai-inference.svc.cluster.local:6333"
      "KF_SEARXNG_URL=http://searxng.search.svc.cluster.local:7777"
      "KF_VALKEY_URL=valkey://valkey.search.svc.cluster.local:6379/0"
      "KF_EMBEDDING_MODEL=nomic-ai/nomic-embed-text-v2-moe"
      "KF_LLM_TIER0_URL=http://10.1.1.140:1235/v1"
      "KF_LLM_TIER1_URL=http://10.1.1.110:1235/v1"
      "KF_LLM_TIER2_URL=http://10.1.1.110:1234/v1"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "REQUESTS_CA_BUNDLE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "HF_HOME=${embeddingModelCache}"
      "HF_HUB_OFFLINE=1"
      "HOME=/tmp"
    ];
    WorkingDir = "/app";
    Labels = {
      "org.opencontainers.image.title" = "Knowledge Fabric Engine";
      "org.opencontainers.image.description" = "Self-hosted knowledge management, search, and research engine";
    };
  };
}
