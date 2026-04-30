{
 lib,
 fetchFromGitHub,
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
 pname = "llama-cpp-vulkan-turbo";
 version = "0-unstable-2026-04-30";

 # SpiritLuna's llama.cpp fork with TurboQuant + TriAttention + DFlash
 src = fetchFromGitHub {
 owner = "SpiritLuna";
 repo = "llama.cpp";
 rev = "triattention";  # or latest commit hash
 hash = "sha256-PLACEHOLDER";  # Will need to be filled with actual hash
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
 "-DGGML_CUDA=OFF"  # No CUDA for Vulkan-only build
 "-DCMAKE_BUILD_TYPE=Release"
 "-DCMAKE_SKIP_BUILD_RPATH=TRUE"
 "-DGGML_AVX2=ON"
 "-DGGML_FMA=ON"
 "-DGGML_F16C=ON"
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
 description = "Inference of LLaMA model with Vulkan + TurboQuant optimizations";
 homepage = "https://github.com/SpiritLuna/llama.cpp";
 license = lib.licenses.mit;
 platforms = lib.platforms.linux;
 };
}
