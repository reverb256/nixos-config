#include <iostream>
#include <chrono>
#include <thread>
#include "config.hpp"
#include "ssl_utils.hpp"
#include "stratum.hpp"

int main(int argc, char* argv[]) {
    std::string config_path = "/etc/gpu-proxy/config.json";

    for (int i = 1; i < argc; i++) {
        if (std::string(argv[i]) == "--config" && i + 1 < argc) {
            config_path = argv[++i];
        }
    }

    try {
        auto config = gpu_proxy::ConfigLoader::load_from_file(config_path);

        if (config.pools.empty()) {
            std::cerr << "No pools configured" << std::endl;
            return 1;
        }

        const auto& pool = config.pools[0];  // Use first pool
        std::cout << "Testing connection to " << pool.name
                  << " at " << pool.host << ":" << pool.port << std::endl;

        gpu_proxy::TLSConnection conn(pool.host, pool.port);

        if (!conn.connect()) {
            std::cerr << "Failed to connect" << std::endl;
            return 1;
        }

        std::cout << "Connected successfully!" << std::endl;

        // Send subscribe immediately (some pools require this before authorize)
        std::string subscribe_msg = R"({"id": 1, "method": "mining.subscribe", "params": ["gpu-proxy/2.0", null]})";
        if (conn.send_line(subscribe_msg)) {
            std::cout << "Sent subscribe" << std::endl;
        }

        // Small delay then send authorize
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        std::string auth_msg = R"({"id": 2, "method": "mining.authorize", "params":[")"
            + pool.wallet + R"(", "x"]})";
        if (conn.send_line(auth_msg)) {
            std::cout << "Sent authorize for " << pool.wallet << std::endl;
        }

        // Now wait for responses
        for (int i = 0; i < 15; i++) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
            std::string line = conn.recv_line(5);
            if (!line.empty()) {
                std::cout << "Received: " << line << std::endl;
            }
        }

        std::cout << "Test complete - check for 'mining.notify' above" << std::endl;
        return 0;

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
}
