# C++ GPU Proxy Design Document

**Date:** 2026-03-14
**Status:** Design Phase
**Goal:** Rewrite gpu-proxy in C++ with OpenSSL for Kryptex compatibility

## Problem Statement

Python's TLS implementation (both `ssl` module and PyOpenSSL) cannot receive data from Kryptex CR29 pools. xmrig-proxy (C++ with OpenSSL) works perfectly with the same pools.

## Requirements

### Functional Requirements
1. **Stratum Protocol Support**
   - Handle JSON-RPC over TCP
   - mining.subscribe
   - mining.authorize
   - mining.notify (job distribution)
   - mining.submit (share submission)
   - mining.set_difficulty

2. **Multi-Pool Failover**
   - Primary pool: Kryptex US
   - Secondary pool: Kryptex EU
   - Automatic failover on connection loss
   - Reconnect with exponential backoff

3. **Worker Management**
   - Multiple miner connections
   - Worker whitelist (optional)
   - Per-worker statistics

4. **TLS Support**
   - OpenSSL-based TLS 1.2+
   - Compatible with Kryptex CR29
   - Optional TLS for miner connections

5. **Configuration**
   - JSON config file (compatible with existing)
   - Command-line arguments

### Non-Functional Requirements
- **Performance:** Handle 100+ concurrent miner connections
- **Memory:** < 50MB RSS
- **Reliability:** Graceful degradation on errors
- **Logging:** Structured logs (journald integration)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         GPU Proxy (C++)                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐     ┌─────────────────┐     ┌─────────────┐ │
│  │  Config      │────▶│ Pool Manager    │────▶│ Pool A      │ │
│  │  Loader      │     │ (failover logic)│     │ (Kryptex)   │ │
│  └──────────────┘     └─────────────────┘     └─────────────┘ │
│                                │                       │
│                                │▶ Failover             │
│                                │                       │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │              Worker Manager                             │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐ │  │
│  │  │Miner 1  │  │Miner 2  │  │Miner 3  │  │Miner N  │ │  │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘ │  │
│  │       │            │            │            │        │  │
│  │       └────────────┴────────────┴────────────┘        │  │
│  │                       │                                │  │
│  │                       ▼                                │  │
│  │              ┌─────────────────┐                      │  │
│  │              │ Job Distributor │                      │  │
│  │              └─────────────────┘                      │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                   API Server (HTTP)                        │  │
│  │              /stats, /workers, /pools                    │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

## Component Design

### 1. Main Loop (Event-Driven)
- **Library:** libevent / epoll
- **Pattern:** Reactor pattern
- **Responsibility:** I/O multiplexing, timer events

### 2. Connection Pool
- **Pool connections:** Persistent with heartbeat
- **Miner connections:** Accept from miners, track state
- **Protocol:** JSON-RPC over TCP (newline delimited)

### 3. TLS Layer
- **Library:** OpenSSL
- **Configuration:**
  ```cpp
  SSL_CTX* ctx = SSL_CTX_new(TLS_client_method());
  SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
  SSL_CTX_set_cipher_list(ctx, "DEFAULT:@SECLEVEL=0");
  SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, nullptr);
  ```

### 4. Stratum Protocol Handler
- **JSON Parser:** nlohmann/json
- **Message routing:** By method field
- **Job caching:** Current job per pool

### 5. Configuration
- **Format:** JSON (compatible with existing)
- **Hot reload:** SIGHUP handler

## Data Structures

```cpp
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

struct Job {
    std::string job_id;
    std::string blob;
    std::string target;
    std::string difficulty;
    uint64_t height;
    bool clean_jobs;
};
```

## File Structure

```
gpu-proxy-cpp/
├── CMakeLists.txt
├── src/
│   ├── main.cpp
│   ├── config.cpp
│   ├── config.hpp
│   ├── ssl_utils.cpp
│   ├── ssl_utils.hpp
│   ├── connection.cpp
│   ├── connection.hpp
│   ├── pool_manager.cpp
│   ├── pool_manager.hpp
│   ├── worker_manager.cpp
│   ├── worker_manager.hpp
│   ├── stratum_handler.cpp
│   ├── stratum_handler.hpp
│   ├── api_server.cpp
│   └── api_server.hpp
└── tests/
```

## NixOS Integration

```nix
gpu-proxy-cpp-package = pkgs.stdenv.mkDerivation {
  pname = "gpu-proxy-cpp";
  version = "2.0.0";

  src = ./gpu-proxy-cpp;

  nativeBuildInputs = with pkgs; [ cmake pkg-config ];
  buildInputs = with pkgs; [ openssl nlohmann_json libevent ];

  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];
};
```

## Testing Strategy

1. **Unit Tests:** Google Test
   - JSON parsing
   - TLS handshake
   - Pool failover logic

2. **Integration Tests:**
   - Connect to test pool
   - Miner connection
   - Job distribution

3. **Manual Testing:**
   - Run alongside existing Python proxy
   - Compare logs
   - Verify hashrate

## Implementation Phases

### Phase 1: Core Functionality (8-12 hours)
- Basic TCP server/client
- JSON parsing
- Stratum protocol handling
- OpenSSL TLS integration

### Phase 2: Pool & Worker Management (4-6 hours)
- Multi-pool failover
- Worker tracking
- Job distribution

### Phase 3: Production Features (4-6 hours)
- Configuration file loading
- Logging
- API server
- Signal handling

### Phase 4: Integration & Testing (2-4 hours)
- NixOS packaging
- Deployment
- Testing

**Total Estimate:** 18-28 hours

## Success Criteria

- ✅ Connects to Kryptex CR29 successfully
- ✅ Receives jobs and distributes to miners
- ✅ Miners show hashrate > 0
- ✅ Failover works when primary pool fails
- ✅ Memory usage < 50MB
- ✅ No memory leaks (valgrind clean)
