cmake_minimum_required(VERSION 3.15)
project(gpu-proxy VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# OpenSSL and nlohmann_json - will be provided by NixOS build environment
# For manual testing, you may need to set:
#   CMAKE_INCLUDE_PATH and CMAKE_LIBRARY_PATH

find_package(OpenSSL REQUIRED)
find_package(nlohmann_json 3.10.0 REQUIRED)

add_executable(gpu-proxy
    src/main.cpp
)

target_link_libraries(gpu-proxy
    OpenSSL::SSL
    OpenSSL::Crypto
    nlohmann_json::nlohmann_json
    pthread
)

# Installation
install(TARGETS gpu-proxy DESTINATION bin)
