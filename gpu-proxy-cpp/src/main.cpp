#include <iostream>
#include "config.hpp"

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " --config <path>" << std::endl;
        return 1;
    }

    std::string config_path;
    for (int i = 1; i < argc; i++) {
        if (std::string(argv[i]) == "--config" && i + 1 < argc) {
            config_path = argv[++i];
        }
    }

    try {
        auto config = gpu_proxy::ConfigLoader::load_from_file(config_path);
        std::cout << "Loaded config with " << config.pools.size() << " pools" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
