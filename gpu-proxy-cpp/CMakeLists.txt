cmake_minimum_required(VERSION 3.15)
project(gpu-proxy VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Find OpenSSL
find_package(OpenSSL REQUIRED)

# nlohmann_json is header-only - just need the include path
# Try to find it, or let NixOS provide it via buildInputs
find_path(NLOHMANN_JSON_INCLUDE_DIR nlohmann/json.hpp
    PATHS
        /nix/store/*/nlohmann_json-*/include
        /run/current-system/sw/include
    NO_DEFAULT_PATH
)

if(NOT NLOHMANN_JSON_INCLUDE_DIR)
    message(WARNING "nlohmann/json.hpp not found - will rely on NixOS buildInputs")
    set(NLOHMANN_JSON_INCLUDE_DIR "")
endif()

add_executable(gpu-proxy
    src/main.cpp
)

target_include_directories(gpu-proxy PRIVATE ${NLOHMANN_JSON_INCLUDE_DIR})
target_link_libraries(gpu-proxy
    OpenSSL::SSL
    OpenSSL::Crypto
    pthread
)

# Installation
install(TARGETS gpu-proxy DESTINATION bin)
