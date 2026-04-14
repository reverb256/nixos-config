# Minimal OCI image for llama.cpp server with ROCm
# ~2GB vs ~20GB for upstream ghcr.io image
{ pkgs }:

pkgs.dockerTools.buildLayeredImage {
  name = "llama-cpp-rocm";
  tag = "latest";

  contents = with pkgs; [
    llama-cpp-rocm
    bashInteractive
    coreutils
    cacert
  ];

  config = {
    Entrypoint = [ "/bin/llama-server" ];
    Env = [
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "ROC_ENABLE_PRE_VEGA=1"
    ];
  };
}
