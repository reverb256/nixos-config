# Pure Vulkan llama.cpp — no CUDA support for hosts where NVIDIA GPUs are busy mining
{ lib, fetchFromGitHub, cmake, pkg-config, python3, gtest, spdlog, vulkan-headers, vulkan-loader, shaderc, glslang, stdenv }:

stdenv.mkDerivation (finalAttrs: {
  pname = "llama-cpp-vulkan-nocuda";
  version = "b9048-vulkan-nocuda";

  src = fetchFromGitHub {
    owner = "ggerganov";
    repo = "llama.cpp";
    rev = "b9048";
    sha256 = "sha256-fveIwM5q/PN3bJAS+T6EmIobSsTHw7e2Q9DWIwunS4Q=";
  };

  nativeBuildInputs = [ cmake pkg-config python3 ];
  buildInputs = [ vulkan-headers vulkan-loader shaderc glslang gtest spdlog ];

  cmakeFlags = [
    "-DGGML_VULKAN=ON"
    "-DGGML_CUDA=OFF"
    "-DGGML_METAL=OFF"
    "-DLLAMA_BUILD_TESTS=OFF"
    "-DLLAMA_BUILD_EXAMPLES=ON"
  ];

  doCheck = false;

  postFixup = ''
    substituteInPlace $out/bin/llama-cli --replace 'LLAMA_BUILD_NUMBER' '${finalAttrs.version}'
  '';

  meta = with lib; {
    description = "Pure Vulkan llama.cpp — no CUDA support for mining hosts";
    homepage = "https://github.com/ggerganov/llama.cpp";
    license = licenses.mit;
    platforms = platforms.linux;
  };
})