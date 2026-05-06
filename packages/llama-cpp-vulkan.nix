{
  lib,
  fetchurl,
  cmake,
  ninja,
  stdenv,
  vulkan-headers,
  vulkan-loader,
  shaderc,
  glslang,
  pkg-config,
}:
stdenv.mkDerivation rec {
  pname = "llama-cpp-vulkan";
  version = "0-unstable-2026-05-06";
  src = fetchurl {
    url = "https://github.com/ggerganov/llama.cpp/archive/5207d120eac2.tar.gz";
    hash = "sha256-VCKlG8HfS/e7vn9h1BSV2HrL2+m1mTfjeqNmkjdPH5Q=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    vulkan-headers
    vulkan-loader
    shaderc
    glslang
  ];

  cmakeFlags = [
    "-DGGML_NATIVE=OFF"
    "-DLLAMA_BUILD_EXAMPLES=OFF"
    "-DLLAMA_BUILD_SERVER=ON"
    "-DLLAMA_BUILD_TESTS=OFF"
    "-DBUILD_SHARED_LIBS=ON"
    "-DLLAMA_OPENSSL=OFF"
    "-DGGML_VULKAN=ON"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_SKIP_BUILD_RPATH=TRUE"
  ];

  postInstall = ''
    ln -sf $out/bin/llama-cli $out/bin/llama
  '';

  preFixup = ''
    for f in $(find $out -type f -executable 2>/dev/null); do
      ${stdenv.cc.bintools.targetPrefix}patchelf --shrink-rpath "$f" 2>/dev/null || true
    done
  '';

  meta = {
    description = "Inference of LLaMA model (and others) in pure C/C++ with Vulkan support";
    homepage = "https://github.com/ggerganov/llama.cpp";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
