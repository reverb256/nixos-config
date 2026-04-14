{
  lib,
  fetchurl,
  rocmPackages,
  cmake,
  ninja,
  stdenv,
  autoAddDriverRunpath,
}:
stdenv.mkDerivation rec {
  pname = "llama-cpp-rocm";
  version = "0-unstable-2026-04-14";
  src = fetchurl {
    url = "https://github.com/ggerganov/llama.cpp/archive/6a6780a232b73fe44799b0c0d5f01c61612f1b79.tar.gz";
    hash = "sha256-RQXDx//OHJLTRytABGIY7E8AVAMQOmWcJ3czTsHEkGc=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    autoAddDriverRunpath
  ];

  buildInputs = with rocmPackages; [
    clr
    rocblas
    hipblas
  ];

  cmakeFlags = [
    "-DGGML_NATIVE=OFF"
    "-DLLAMA_BUILD_EXAMPLES=OFF"
    "-DLLAMA_BUILD_SERVER=ON"
    "-DLLAMA_BUILD_TESTS=OFF"
    "-DBUILD_SHARED_LIBS=ON"
    "-DLLAMA_OPENSSL=OFF"
    "-DGGML_HIP=ON"
    "-DGGML_HIP_UMA=OFF"
    "-DCMAKE_HIP_COMPILER=${rocmPackages.clr.hipClangPath}/clang++"
    "-DCMAKE_HIP_ARCHITECTURES=gfx1010"
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
    description = "Inference of Meta's LLaMA model (and others) in pure C/C++ with ROCm support";
    homepage = "https://github.com/ggerganov/llama.cpp";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
