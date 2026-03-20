# C++ GPU Proxy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite gpu-proxy in C++ with OpenSSL to achieve compatibility with Kryptex CR29 mining pools (which Python's TLS cannot achieve)

**Architecture:** Event-driven C++ server using libevent for I/O multiplexing, OpenSSL for TLS 1.2+ connections, and JSON-RPC stratum protocol handling

**Tech Stack:** C++17, OpenSSL, nlohmann/json, libevent, spdlog (optional - can use stdout for simplicity)

---

## Task 1: Project Skeleton

**Files:**
- Create: `gpu-proxy-cpp/CMakeLists.txt`
- Create: `gpu-proxy-cpp/src/main.cpp`
- Create: `gpu-proxy-cpp/.gitignore`

**Step 1: Create CMakeLists.txt**

```cmake
cmake_minimum_required(VERSION 3.15)
project(gpu-proxy VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(OpenSSL REQUIRED)
find_package(nlohmann_json 3.10.0 REQUIRED)

# Simplified: use poll() instead of libevent dependency
# This reduces external dependencies

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
```

**Step 2: Create .gitignore**

```
build/
*.o
*.a
.clangd
.compile_commands.json
```

**Step 3: Create minimal main.cpp**

```cpp
#include <iostream>

int main() {
    std::cout << "GPU Proxy v2.0.0 - C++ with OpenSSL" << std::endl;
    return 0;
}
```

**Step 4: Test build**

```bash
cd /etc/nixos/gpu-proxy-cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/gpu-proxy
```

Expected output: `GPU Proxy v2.0.0 - C++ with OpenSSL`

**Step 5: Commit**

```bash
git add gpu-proxy-cpp
git commit -m "feat(cpp-proxy): add project skeleton"
```

---

## Task 2: Configuration Loading

**Files:**
- Create: `gpu-proxy-cpp/src/config.hpp`
- Create: `gpu-proxy-cpp/src/config.cpp`
- Modify: `gpu-proxy-cpp/src/main.cpp`

**Step 1: Create config.hpp**

```cpp
#pragma once
#include <string>
#include <vector>
#include <cstdint>

namespace gpu_proxy {

struct PoolConfig {
    std::string name;
    std::string host;
    uint16_t port;
    std::string wallet;
    std::string password;
    bool tls;
    int priority;
};

struct WorkerConfig {
    std::string id;
    std::string password;
};

struct ProxyConfig {
    uint16_t listen_port;
    uint16_t api_port;
    std::string log_level;
    std::vector<PoolConfig> pools;
    std::vector<WorkerConfig> workers;
};

class ConfigLoader {
public:
    static ProxyConfig load_from_file(const std::string& path);
    static ProxyConfig load_default();  // For testing
};

} // namespace gpu_proxy
```

**Step 2: Create config.cpp**

```cpp
#include "config.hpp"
#include <fstream>
#include <nlohmann/json.hpp>

namespace gpu_proxy {

ProxyConfig ConfigLoader::load_from_file(const std::string& path) {
    std::ifstream file(path);
    if (!file) {
        throw std::runtime_error("Cannot open config file: " + path);
    }

    nlohmann::json j;
    file >> j;

    ProxyConfig config;

    // Parse settings
    if (j.contains("settings")) {
        const auto& settings = j["settings"];
        if (settings.contains("listen_port")) settings["listen_port"].get_to(config.listen_port);
        if (settings.contains("api_port")) settings["api_port"].get_to(config.api_port);
        if (settings.contains("log_level")) settings["log_level"].get_to(config.log_level);
    }

    // Parse pools
    if (j.contains("pools")) {
        for (const auto& p : j["pools"]) {
            PoolConfig pool;
            p["name"].get_to(pool.name);
            p["url"].get_to(pool.host);  // Will parse host:port later
            p["wallet"].get_to(pool.wallet);
            p["password"].get_to(pool.password);
            p["tls"].get_to(pool.tls);
            p["priority"].get_to(pool.priority);
            config.pools.push_back(pool);
        }
    }

    // Parse workers
    if (j.contains("workers")) {
        for (const auto& w : j["workers"]) {
            WorkerConfig worker;
            w["id"].get_to(worker.id);
            w["password"].get_to(worker.password);
            config.workers.push_back(worker);
        }
    }

    return config;
}

ProxyConfig ConfigLoader::load_default() {
    ProxyConfig config;
    config.listen_port = 3334;
    config.api_port = 8083;
    config.log_level = "INFO";
    return config;
}

} // namespace gpu_proxy
```

**Step 3: Update main.cpp to test config loading**

```cpp
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
```

**Step 4: Test build**

```bash
cmake --build build
./build/gpu-proxy --config /etc/gpu-proxy/config.json
```

Expected: `Loaded config with 2 pools`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat(cpp-proxy): add configuration loading"
```

---

## Task 3: OpenSSL TLS Connection

**Files:**
- Create: `gpu-proxy-cpp/src/ssl_utils.hpp`
- Create: `gpu-proxy-cpp/src/ssl_utils.cpp`

**Step 1: Create ssl_utils.hpp**

```cpp
#pragma once
#include <string>
#include <memory>

struct ssl_st;  // Forward declare SSL
typedef struct ssl_st SSL;

namespace gpu_proxy {

class TLSConnection {
public:
    TLSConnection(const std::string& host, uint16_t port);
    ~TLSConnection();

    bool connect();
    void disconnect();
    bool is_connected() const { return connected_; }

    // Send line (adds newline)
    bool send_line(const std::string& line);

    // Receive line (reads until newline)
    std::string recv_line(int timeout_sec = 30);

private:
    std::string host_;
    uint16_t port_;
    int socket_fd_ = -1;
    SSL* ssl_ = nullptr;
    SSL_CTX* ctx_ = nullptr;
    bool connected_ = false;

    bool create_ssl_context();
    bool perform_ssl_handshake();
};

} // namespace gpu_proxy
```

**Step 2: Create ssl_utils.cpp**

```cpp
#include "ssl_utils.hpp"
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

namespace gpu_proxy {

TLSConnection::TLSConnection(const std::string& host, uint16_t port)
    : host_(host), port_(port) {}

TLSConnection::~TLSConnection() {
    disconnect();
}

bool TLSConnection::create_ssl_context() {
    // Create SSL context (client method)
    const SSL_METHOD* method = TLS_client_method();
    ctx_ = SSL_CTX_new(method);
    if (!ctx_) {
        return false;
    }

    // Set minimum protocol version to TLS 1.2
    SSL_CTX_set_min_proto_version(ctx_, TLS1_2_VERSION);

    // Set cipher list for maximum compatibility
    // This matches xmrig-proxy settings
    if (SSL_CTX_set_cipher_list(ctx_, "DEFAULT:@SECLEVEL=0") <= 0) {
        SSL_CTX_free(ctx_);
        ctx_ = nullptr;
        return false;
    }

    // Disable certificate verification (pools use self-signed)
    SSL_CTX_set_verify(ctx_, SSL_VERIFY_NONE, nullptr);

    return true;
}

bool TLSConnection::perform_ssl_handshake() {
    ssl_ = SSL_new(ctx_);
    if (!ssl_) {
        return false;
    }

    // Set SNI hostname
    SSL_set_tlsext_host_name(ssl_, host_.c_str());

    // Create SSL file descriptor
    int ssl_fd = SSL_get_fd(ssl_);
    if (!SSL_set_fd(ssl_, socket_fd_)) {
        SSL_free(ssl_);
        ssl_ = nullptr;
        return false;
    }

    // Perform SSL handshake
    int ret = SSL_connect(ssl_);
    if (ret != 1) {
        int err = SSL_get_error(ssl_, ret);
        // Handle SSL_ERROR_WANT_READ/WRITE properly in non-blocking mode
        // For blocking mode, ret == 1 means success
        SSL_free(ssl_);
        ssl_ = nullptr;
        return false;
    }

    return true;
}

bool TLSConnection::connect() {
    // Create socket
    socket_fd_ = socket(AF_INET, SOCK_STREAM, 0);
    if (socket_fd_ < 0) {
        return false;
    }

    // Set socket to blocking mode (simpler for initial implementation)
    int flags = fcntl(socket_fd_, F_GETFL, 0);
    fcntl(socket_fd_, F_SETFL, flags & ~O_NONBLOCK);

    // Connect to host
    struct sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port_);

    if (inet_pton(AF_INET, host_.c_str(), &addr.sin_addr) <= 0) {
        // Need DNS resolution - use gethostbyname for now
        struct hostent* he = gethostbyname(host_.c_str());
        if (!he) {
            ::close(socket_fd_);
            socket_fd_ = -1;
            return false;
        }
        memcpy(&addr.sin_addr, he->h_addr_list[0], he->h_length);
    }

    if (::connect(socket_fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        ::close(socket_fd_);
        socket_fd_ = -1;
        return false;
    }

    // Create SSL context and perform handshake
    if (!create_ssl_context()) {
        ::close(socket_fd_);
        socket_fd_ = -1;
        return false;
    }

    if (!perform_ssl_handshake()) {
        SSL_CTX_free(ctx_);
        ctx_ = nullptr;
        ::close(socket_fd_);
        socket_fd_ = -1;
        return false;
    }

    connected_ = true;
    return true;
}

void TLSConnection::disconnect() {
    if (ssl_) {
        SSL_shutdown(ssl_);
        SSL_free(ssl_);
        ssl_ = nullptr;
    }
    if (ctx_) {
        SSL_CTX_free(ctx_);
        ctx_ = nullptr;
    }
    if (socket_fd_ >= 0) {
        ::close(socket_fd_);
        socket_fd_ = -1;
    }
    connected_ = false;
}

bool TLSConnection::send_line(const std::string& line) {
    if (!connected_) return false;

    std::string full_line = line + "\n";
    int sent = SSL_write(ssl_, full_line.c_str(), full_line.length());
    return sent == static_cast<int>(full_line.length());
}

std::string TLSConnection::recv_line(int timeout_sec) {
    if (!connected_) return "";

    std::string result;
    char buf[1024];

    while (true) {
        int received = SSL_read(ssl_, buf, sizeof(buf) - 1);
        if (received <= 0) {
            int err = SSL_get_error(ssl_, received);
            if (err == SSL_ERROR_ZERO_RETURN) {
                // Clean shutdown
                break;
            }
            if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
                // In non-blocking mode, would retry
                continue;
            }
            // Error
            break;
        }

        buf[received] = '\0';
        result += buf;

        // Check if we have a complete line
        if (result.find('\n') != std::string::npos) {
            break;
        }
    }

    // Trim at newline
    size_t newline_pos = result.find('\n');
    if (newline_pos != std::string::npos) {
        result = result.substr(0, newline_pos);
    }

    return result;
}

} // namespace gpu_proxy
```

**Step 3: Update CMakeLists.txt to link openssl**

Already done in Task 1 (find_package(OpenSSL REQUIRED))

**Step 4: Test build**

```bash
cmake --build build
```

Expected: Clean build

**Step 5: Commit**

```bash
git add -A
git commit -m "feat(cpp-proxy): add OpenSSL TLS connection layer"
```

---

## Task 4: Stratum Protocol Handler

**Files:**
- Create: `gpu-proxy-cpp/src/stratum.hpp`
- Create: `gpu-proxy-cpp/src/stratum.cpp`

**Step 1: Create stratum.hpp**

```cpp
#pragma once
#include <string>
#include <nlohmann/json.hpp>

namespace gpu_proxy {

enum class StratumMethod {
    SUBSCRIBE,
    AUTHORIZE,
    SUBMIT,
    NOTIFY,
    SET_DIFFICULTY,
    UNKNOWN
};

struct StratumRequest {
    int id;
    StratumMethod method;
    nlohmann::json params;

    static StratumRequest parse(const std::string& line);
};

struct StratumResponse {
    int id;
    nlohmann::json result;
    nlohmann::json error;

    std::string to_json() const;
};

struct Job {
    std::string job_id;
    std::string blob;
    std::string target;
    std::string difficulty;
    uint64_t height;
    bool clean_jobs;

    static Job from_notify(const nlohmann::json& params);
};

} // namespace gpu_proxy
```

**Step 2: Create stratum.cpp**

```cpp
#include "stratum.hpp"
#include <sstream>
#include <algorithm>

namespace gpu_proxy {

StratumRequest StratumRequest::parse(const std::string& line) {
    StratumRequest req;

    try {
        nlohmann::json j = nlohmann::json::parse(line);

        if (j.contains("id")) j["id"].get_to(req.id);
        else req.id = 0;  // Notifications have no id

        if (j.contains("method")) {
            std::string method_str;
            j["method"].get_to(method_str);

            if (method_str == "mining.subscribe") req.method = StratumMethod::SUBSCRIBE;
            else if (method_str == "mining.authorize") req.method = StratumMethod::AUTHORIZE;
            else if (method_str == "mining.submit") req.method = StratumMethod::SUBMIT;
            else if (method_str == "mining.notify") req.method = StratumMethod::NOTIFY;
            else if (method_str == "mining.set_difficulty") req.method = StratumMethod::SET_DIFFICULTY;
            else req.method = StratumMethod::UNKNOWN;
        } else {
            req.method = StratumMethod::UNKNOWN;
        }

        if (j.contains("params")) {
            j["params"].get_to(req.params);
        }

    } catch (const nlohmann::json::exception& e) {
        req.method = StratumMethod::UNKNOWN;
    }

    return req;
}

std::string StratumResponse::to_json() const {
    nlohmann::json j;
    j["id"] = id;
    j["result"] = result;
    j["error"] = error;
    return j.dump();
}

Job Job::from_notify(const nlohmann::json& params) {
    Job job;

    if (params.is_array() && params.size() >= 4) {
        job.job_id = params[0];
        job.blob = params[1];  // Extra nonce2
        job.target = params[2];
        job.difficulty = params[3];

        if (params.size() >= 5) {
            params[4].get_to(job.height);
        }

        if (params.size() >= 6) {
            params[5].get_to(job.clean_jobs);
        }
    }

    return job;
}

} // namespace gpu_proxy
```

**Step 3: Test build**

```bash
cmake --build build
```

**Step 4: Commit**

```bash
git add -A
git commit -m "feat(cpp-proxy): add stratum protocol handler"
```

---

## Task 5: Simple Pool Connection Test

**Files:**
- Modify: `gpu-proxy-cpp/src/main.cpp`

**Step 1: Update main.cpp to test pool connection**

```cpp
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

        // Send subscribe
        std::string subscribe_msg = R"({"id": 1, "method": "mining.subscribe", "params": ["gpu-proxy/2.0", null]})";
        if (conn.send_line(subscribe_msg)) {
            std::cout << "Sent subscribe" << std::endl;
        }

        // Wait for response
        std::this_thread::sleep_for(std::chrono::seconds(2));
        std::string response = conn.recv_line();
        if (!response.empty()) {
            std::cout << "Received: " << response << std::endl;
        }

        // Send authorize
        std::string auth_msg = R"({"id": 2, "method": "mining.authorize", "params":[")"
            + pool.wallet + R"(", "x"]})";
        if (conn.send_line(auth_msg)) {
            std::cout << "Sent authorize" << std::endl;
        }

        // Wait for more responses
        for (int i = 0; i < 10; i++) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
            std::string line = conn.recv_line();
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
```

**Step 2: Test build**

```bash
cmake --build build
```

**Step 3: Deploy to Nexus and test**

```bash
just deploy  # Or copy to nexus and run there
ssh nexus 'cd /etc/nixos && nix build .#nixosConfigurations.nexus.config.system.build.toplevel && nixos-rebuild switch'
```

**Step 4: Run test on Nexus**

```bash
ssh nexus 'cd /etc/nixos/gpu-proxy-cpp && build/build/gpu-proxy --config /etc/gpu-proxy/config.json'
```

**Expected:** Should receive JSON responses from Kryptex, including `mining.notify` jobs.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat(cpp-proxy): add pool connection test in main"
```

---

## Task 6: TCP Server for Miner Connections

**Files:**
- Create: `gpu-proxy-cpp/src/server.hpp`
- Create: `gpu-proxy-cpp/src/server.cpp`

**Step 1: Create server.hpp**

```cpp
#pragma once
#include <functional>
#include <memory>
#include <string>
#include <stdint.h>

namespace gpu_proxy {

class TCPServer {
public:
    using ConnectionCallback = std::function<void(int fd)>;

    TCPServer(uint16_t port);
    ~TCPServer();

    bool start();
    void stop();
    void set_connection_callback(ConnectionCallback cb);

private:
    uint16_t port_;
    int listen_fd_ = -1;
    bool running_ = false;
    ConnectionCallback connection_callback_;

    void accept_loop();
};

} // namespace gpu_proxy
```

**Step 2: Create server.cpp**

```cpp
#include "server.hpp"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <thread>

namespace gpu_proxy {

TCPServer::TCPServer(uint16_t port) : port_(port) {}

TCPServer::~TCPServer() {
    stop();
}

void TCPServer::set_connection_callback(ConnectionCallback cb) {
    connection_callback_ = std::move(cb);
}

bool TCPServer::start() {
    listen_fd_ = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd_ < 0) {
        return false;
    }

    int opt = 1;
    setsockopt(listen_fd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port_);

    if (bind(listen_fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        ::close(listen_fd_);
        listen_fd_ = -1;
        return false;
    }

    if (listen(listen_fd_, 50) < 0) {
        ::close(listen_fd_);
        listen_fd_ = -1;
        return false;
    }

    running_ = true;
    return true;
}

void TCPServer::stop() {
    running_ = false;
    if (listen_fd_ >= 0) {
        ::close(listen_fd_);
        listen_fd_ = -1;
    }
}

void TCPServer::accept_loop() {
    while (running_) {
        struct sockaddr_in client_addr{};
        socklen_t addr_len = sizeof(client_addr);

        int client_fd = accept(listen_fd_, (struct sockaddr*)&client_addr, &addr_len);
        if (client_fd < 0) {
            if (running_) continue;
            break;
        }

        if (connection_callback_) {
            connection_callback_(client_fd);
        }
    }
}

} // namespace gpu_proxy
```

**Step 3: Update CMakeLists.txt**

```cmake
add_executable(gpu-proxy
    src/main.cpp
    src/server.cpp
    src/ssl_utils.cpp
    src/stratum.cpp
)
```

**Step 4: Test build**

```bash
cmake --build build
```

**Step 5: Commit**

```bash
git add -A
git commit -m "feat(cpp-proxy): add TCP server for miner connections"
```

---

## Task 7: Full Proxy Implementation

**Files:**
- Modify: `gpu-proxy-cpp/src/main.cpp` (complete rewrite)
- Create: `gpu-proxy-cpp/src/proxy.hpp`
- Create: `gpu-proxy-cpp/src/proxy.cpp`

**Step 1: Create proxy.hpp**

```cpp
#pragma once
#include "config.hpp"
#include "ssl_utils.hpp"
#include "stratum.hpp"
#include "server.hpp"
#include <memory>
#include <map>
#include <vector>

namespace gpu_proxy {

class MinerConnection {
public:
    MinerConnection(int fd, const std::string& worker_id);

    bool send_message(const std::string& json_msg);
    std::string receive_message();
    void close();

    int get_fd() const { return fd_; }
    const std::string& get_worker_id() const { return worker_id_; }

private:
    int fd_;
    std::string worker_id_;
    bool authorized_ = false;
};

class Proxy {
public:
    Proxy(const ProxyConfig& config);

    bool start();
    void stop();

private:
    ProxyConfig config_;
    TCPServer server_;

    std::unique_ptr<TLSConnection> pool_connection_;
    std::map<int, std::unique_ptr<MinerConnection>> miners_;

    Job current_job_;

    bool connect_to_pool();
    void handle_miner_message(int miner_fd, const std::string& msg);
    void broadcast_job_to_miners();
    void forward_to_pool(const std::string& msg);
};

} // namespace gpu_proxy
```

**Step 2: Create proxy.cpp**

```cpp
#include "proxy.hpp"
#include <iostream>
#include <sstream>
#include <algorithm>
#include <sys/select.h>
#include <unistd.h>
#include <cstring>

namespace gpu_proxy {

MinerConnection::MinerConnection(int fd, const std::string& worker_id)
    : fd_(fd), worker_id_(worker_id) {}

bool MinerConnection::send_message(const std::string& json_msg) {
    std::string full_msg = json_msg + "\n";
    int sent = send(fd_, full_msg.c_str(), full_msg.length(), 0);
    return sent == static_cast<int>(full_msg.length());
}

std::string MinerConnection::receive_message() {
    char buf[4096];
    int received = recv(fd_, buf, sizeof(buf) - 1, 0);
    if (received <= 0) return "";

    buf[received] = '\0';
    return std::string(buf);
}

void MinerConnection::close() {
    ::close(fd_);
}

Proxy::Proxy(const ProxyConfig& config)
    : config_(config), server_(config.listen_port) {

    // Find pool with lowest priority (highest priority = 1)
    auto pool_it = std::min_element(config_.pools.begin(), config_.pools.end(),
        [](const PoolConfig& a, const PoolConfig& b) {
            return a.priority < b.priority;
        });

    if (pool_it != config_.pools.end()) {
        pool_connection_ = std::make_unique<TLSConnection>(
            pool_it->host, pool_it->port);
    }

    server_.set_connection_callback([this](int fd) {
        handle_new_miner(fd);
    });
}

bool Proxy::connect_to_pool() {
    if (!pool_connection_) return false;

    if (!pool_connection_->connect()) {
        std::cerr << "Failed to connect to pool" << std::endl;
        return false;
    }

    std::cout << "Connected to pool" << std::endl;

    // Send subscribe
    std::string subscribe = R"({"id": 1, "method": "mining.subscribe", "params": ["gpu-proxy/2.0", null]})";
    pool_connection_->send_line(subscribe);

    // Send authorize with base wallet
    const auto& pool = config_.pools[0];
    std::string auth = R"({"id": 2, "method": "mining.authorize", "params":[")"
        + pool.wallet + R"(", "x"]})";
    pool_connection_->send_line(auth);

    return true;
}

void Proxy::handle_new_miner(int fd) {
    std::cout << "New miner connection: fd=" << fd << std::endl;

    // Will track miner when it authorizes
    // For now, accept all connections
}

void Proxy::handle_miner_message(int miner_fd, const std::string& msg) {
    try {
        auto req = StratumRequest::parse(msg);

        switch (req.method) {
            case StratumMethod::SUBSCRIBE: {
                // Send subscription response
                std::string resp = R"({"id":)" + std::to_string(req.id)
                    + R"(, "result": [[["mining.set_difficulty","1"],["mining.notify","2"]],"deadbeef",4],"error":null})" + "\n";

                auto it = miners_.find(miner_fd);
                if (it != miners_.end()) {
                    it->second->send_message(resp);
                }
                break;
            }

            case StratumMethod::AUTHORIZE: {
                // Extract worker name from params
                if (req.params.is_array() && req.params.size() > 0) {
                    std::string worker_id = req.params[0];

                    // Create miner connection
                    miners_[miner_fd] = std::make_unique<MinerConnection>(miner_fd, worker_id);

                    // Forward to pool
                    std::string pool_auth = R"({"id": 10, "method": "mining.authorize", "params":[")"
                        + worker_id + R"(", "x"]})";
                    pool_connection_->send_line(pool_auth);

                    // Send success response
                    std::string resp = R"({"id":)" + std::to_string(req.id)
                        + R"(, "result":true, "error":null})" + "\n";

                    auto it = miners_.find(miner_fd);
                    if (it != miners_.end()) {
                        it->second->send_message(resp);
                    }

                    // Send current job if available
                    if (!current_job_.job_id.empty()) {
                        // TODO: send job
                    }
                }
                break;
            }

            case StratumMethod::SUBMIT: {
                // Forward to pool
                forward_to_pool(msg);
                break;
            }

            default:
                break;
        }

    } catch (const std::exception& e) {
        std::cerr << "Error handling message: " << e.what() << std::endl;
    }
}

void Proxy::broadcast_job_to_miners() {
    if (current_job_.job_id.empty()) return;

    // TODO: Broadcast job to all authorized miners
}

void Proxy::forward_to_pool(const std::string& msg) {
    if (!pool_connection_ || !pool_connection_->is_connected()) {
        return;
    }

    pool_connection_->send_line(msg);
}

bool Proxy::start() {
    if (!connect_to_pool()) {
        return false;
    }

    if (!server_.start()) {
        return false;
    }

    running_ = true;

    // Main event loop (simplified - use poll in production)
    while (running_) {
        fd_set read_fds;
        FD_ZERO(&read_fds);

        int max_fd = server_.get_listen_fd();
        FD_SET(server_.get_listen_fd(), &read_fds);

        for (const auto& [fd, miner] : miners_) {
            FD_SET(fd, &read_fds);
            if (fd > max_fd) max_fd = fd;
        }

        if (pool_connection_->is_connected()) {
            int pool_fd = pool_connection_->get_socket_fd();
            FD_SET(pool_fd, &read_fds);
            if (pool_fd > max_fd) max_fd = pool_fd;
        }

        struct timeval timeout{.tv_sec = 1};
        int ready = select(max_fd + 1, &read_fds, nullptr, nullptr, &timeout);

        if (ready < 0) {
            if (errno == EINTR) continue;
            break;
        }

        // Check for new miner connections
        if (FD_ISSET(server_.get_listen_fd(), &read_fds)) {
            // Accept new connection (handled by callback)
            struct sockaddr_in client_addr;
            socklen_t addr_len = sizeof(client_addr);
            int client_fd = accept(server_.get_listen_fd(), (struct sockaddr*)&client_addr, &addr_len);
            if (client_fd >= 0) {
                handle_new_miner(client_fd);
            }
        }

        // Check for data from miners
        for (auto it = miners_.begin(); it != miners_.end(); ) {
            int fd = it->first;

            if (FD_ISSET(fd, &read_fds)) {
                char buf[4096];
                int received = recv(fd, buf, sizeof(buf) - 1, 0);

                if (received <= 0) {
                    // Connection closed
                    std::cout << "Miner fd=" << fd << " disconnected" << std::endl;
                    it = miners_.erase(it);
                    ::close(fd);
                    continue;
                }

                buf[received] = '\0';
                std::string msg(buf);
                handle_miner_message(fd, msg);
            }
            ++it;
        }

        // Check for data from pool
        if (pool_connection_ && pool_connection_->is_connected()) {
            // TODO: Receive from pool
        }
    }

    return true;
}

void Proxy::stop() {
    running_ = false;
    server_.stop();

    for (auto& [fd, miner] : miners_) {
        miner->close();
    }
    miners_.clear();

    if (pool_connection_) {
        pool_connection_->disconnect();
    }
}

} // namespace gpu_proxy
```

**Step 3: Update main.cpp**

```cpp
#include <iostream>
#include <csignal>
#include "config.hpp"
#include "proxy.hpp"

std::unique_ptr<gpu_proxy::Proxy> g_proxy;

void signal_handler(int signal) {
    std::cout << "Received signal " << signal << ", shutting down..." << std::endl;
    if (g_proxy) {
        g_proxy->stop();
    }
    exit(0);
}

int main(int argc, char* argv[]) {
    std::string config_path = "/etc/gpu-proxy/config.json";

    for (int i = 1; i < argc; i++) {
        if (std::string(argv[i]) == "--config" && i + 1 < argc) {
            config_path = argv[++i];
        }
    }

    try {
        auto config = gpu_proxy::ConfigLoader::load_from_file(config_path);

        g_proxy = std::make_unique<gpu_proxy::Proxy>(config);

        // Setup signal handlers
        signal(SIGINT, signal_handler);
        signal(SIGTERM, signal_handler);

        std::cout << "GPU Proxy v2.0.0 starting..." << std::endl;

        if (!g_proxy->start()) {
            std::cerr << "Failed to start proxy" << std::endl;
            return 1;
        }

        return 0;

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
}
```

**Step 4: Test build**

```bash
cmake --build build
```

**Step 5: Commit**

```bash
git add -A
git commit -m "feat(cpp-proxy): implement full proxy with miner/pool handling"
```

---

## Task 8: NixOS Integration

**Files:**
- Modify: `modules/mining/gpu-proxy-cpp.nix` (new file)
- Modify: `hosts/nexus/configuration.nix`

**Step 1: Create gpu-proxy-cpp.nix module**

```nix
# GPU Mining Proxy C++ Version
# Uses OpenSSL for TLS compatibility with Kryptex CR29
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.gpu-proxy-cpp;

  gpu-proxy-cpp-package = pkgs.stdenv.mkDerivation {
    pname = "gpu-proxy-cpp";
    version = "2.0.0";

    src = ./gpu-proxy-cpp;

    nativeBuildInputs = with pkgs; [ cmake pkg-config ];
    buildInputs = with pkgs; [ openssl nlohmann_json ];

    cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];

    installPhase = ''
      mkdir -p $out/bin
      cp build/gpu-proxy $out/bin/gpu-proxy-cpp
    '';

    meta = with lib; {
      description = "GPU mining stratum proxy (C++ with OpenSSL)";
      license = licenses.mit;
      platforms = platforms.unix;
    };
  };

in {
  options.services.gpu-proxy-cpp = {
    enable = lib.mkEnableOption "GPU mining stratum proxy (C++ with OpenSSL)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "gpu-proxy";
      description = "User account to run gpu-proxy-cpp";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "gpu-proxy";
      description = "Group account to run gpu-proxy-cpp";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 3334;
      description = "Stratum port to listen on for GPU miners";
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 8084;
      description = "API port for monitoring";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "INFO";
      description = "Log level (DEBUG, INFO, WARNING, ERROR)";
    };

    pools = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Pool name (for logging)";
          };
          url = lib.mkOption {
            type = lib.types.str;
            description = "Pool stratum URL";
          };
          wallet = lib.mkOption {
            type = lib.types.str;
            description = "Wallet address for pool";
          };
          password = lib.mkOption {
            type = lib.types.str;
            default = "x";
            description = "Pool password";
          };
          priority = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "Pool priority (1 = highest)";
          };
          tls = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Use TLS for pool connection";
          };
        };
      });
      description = "List of mining pools with failover configuration";
    };

    workers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          id = lib.mkOption {
            type = lib.types.str;
            description = "Worker ID (e.g., nexus-gpu)";
          };
          password = lib.mkOption {
            type = lib.types.str;
            default = "x";
            description = "Worker password";
          };
        };
      });
      default = [];
      description = "List of allowed worker configurations";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports for gpu-proxy-cpp";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = {
      group = cfg.group;
      isSystemUser = true;
      description = "GPU mining proxy service user (C++)";
    };

    users.groups.${cfg.group} = {};

    # Generate config from pools and workers
    environment.etc."gpu-proxy-cpp/config.json".text = builtins.toJSON {
      pools = cfg.pools;
      workers = cfg.workers;
      settings = {
        listen_port = cfg.listenPort;
        api_port = cfg.apiPort;
        log_level = cfg.logLevel;
      };
    };

    # Firewall
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.listenPort cfg.apiPort];
    };

    # Build and deploy
    system.packages = [gpu-proxy-cpp-package];

    # Systemd service
    systemd.services.gpu-proxy-cpp = {
      description = "GPU Mining Stratum Proxy (C++ with OpenSSL)";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "/var/lib/gpu-proxy-cpp";

        ExecStart = "${gpu-proxy-cpp-package}/bin/gpu-proxy-cpp --config /etc/gpu-proxy-cpp/config.json";

        Restart = "on-failure";
        RestartSec = "10s";

        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = ["/var/lib/gpu-proxy-cpp"];

        MemoryLimit = "100M";
        CPUQuota = "200%";

        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "gpu-proxy-cpp";
      };
    };
  };
}
```

**Step 2: Update Nexus configuration to use C++ proxy**

```nix
    # GPU Proxy C++ version (OpenSSL-based, compatible with Kryptex)
    services.gpu-proxy-cpp = {
      enable = true;
      listenPort = 3334;
      apiPort = 8084;
      logLevel = "INFO";
      pools = [
        {
          name = "Kryptex US";
          url = "xtm-c29-us.kryptext.network:8040";
          wallet = "krxXVNVMM7";
          password = "x";
          priority = 1;
          tls = true;
        }
        {
          name = "Kryptex EU";
          url = "xtm-c29-eu.kryptext.network:8040";
          wallet = "krxXVNVMM7";
          password = "x";
          priority = 2;
          tls = true;
        }
      ];
      workers = [
        {
          id = "krxXVNVMM7.nexus-gpu";
          password = "x";
        }
        {
          id = "krxXVNVMM7.zephyr-gpu";
          password = "x";
        }
        {
          id = "krxXVNVMM7.forge-gpu";
          password = "x";
        }
      ];
      openFirewall = true;
    };
```

**Step 3: Update miners to use port 3334 (C++ proxy)**

No changes needed - miners already use port 3334.

**Step 4: Test and deploy**

```bash
just test
just deploy
```

**Step 5: Verify service is running**

```bash
ssh nexus 'systemctl status gpu-proxy-cpp -l'
ssh nexus 'journalctl -u gpu-proxy-cpp -f'
```

**Step 6: Commit**

```bash
git add modules/mining/gpu-proxy-cpp.nix hosts/nexus/configuration.nix
git commit -m "feat(cpp-proxy): add NixOS module and enable on Nexus"
```

---

## Task 9: Testing and Verification

**Step 1: Check C++ proxy is running**

```bash
ssh nexus 'systemctl status gpu-proxy-cpp'
```

Expected: `active (running)`

**Step 2: Check logs for pool connection**

```bash
ssh nexus 'journalctl -u gpu-proxy-cpp --since "2 minutes ago" | grep -E "(Connected|Received|mining.notify)"'
```

Expected: Should see `Connected to pool` and `mining.notify` messages

**Step 3: Check miner hashrate**

```bash
ssh nexus 'curl -s http://localhost:4068 | jq .'
```

Look for `sol_ps` > 0

**Step 4: Verify failover**

Stop the C++ proxy and check miners fall back to direct pool:
```bash
ssh nexus 'systemctl stop gpu-proxy-cpp'
```

Check miners still show hashrate (using direct Kryptex connection).

**Step 5: Restart proxy**

```bash
ssh nexus 'systemctl start gpu-proxy-cpp'
```

**Step 6: Commit documentation update**

```bash
git add docs/
git commit -m "docs(cpp-proxy): update investigation report with C++ implementation results"
```

---

## Success Criteria Verification

After implementation, verify:

- [ ] C++ proxy connects to Kryptex CR29 successfully
- [ ] Logs show `mining.notify` job messages received
- [ ] Miners show hashrate > 0 g/s through proxy
- [ ] Direct pool failover still works when proxy stopped
- [ ] Memory usage < 100MB (allow some margin)
- [ ] No connection leaks over time

**If all pass:** Python gpu-proxy can be disabled, C++ proxy is primary.

**If any fail:** Debug logs and iterate. The C++ version uses the same OpenSSL as xmrig-proxy, so it should work.

---

**Plan complete and saved to `docs/plans/2026-03-14-cpp-gpu-proxy-implementation.md`.**

**Execution options:**

1. **Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

2. **Manual Execution** - You execute tasks manually from the plan, ask me for help on specific tasks

Which approach would you prefer? Or shall I start executing immediately?
