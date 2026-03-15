# GPU Proxy C++ v2.0.0

High-performance stratum mining proxy written in C++ with OpenSSL for Kryptex CR29 compatibility.

## Problem Solved

The original Python `gpu-proxy` could not receive data from Kryptex CR29 pools due to TLS incompatibility. Python's `ssl` module completes the TLS 1.3 handshake but receives zero bytes of data.

This C++ rewrite uses OpenSSL directly and has been verified to work with Kryptex CR29 pools.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      GPU Proxy (C++)                         │
│                                                             │
│   ┌─────────┐                          ┌──────────────┐     │
│   │ lolMiner│◀─────stratum─────────────▶│ Kryptex Pool │     │
│   │ (N-1)   │       Job Distribution    │   (failover) │     │
│   └─────────┘       Share Forwarding    └──────────────┘     │
│       │                                        │            │
│   ┌───▼────────────────────────────────────────▼───┐        │
│   │              Event Loop (poll)                  │        │
│   │         ┌─────────────────────────┐             │        │
│   │         │  Job Cache (current)    │             │        │
│   │         └─────────────────────────┘             │        │
│   │         ┌─────────────────────────┐             │        │
│   │         │  Worker State (N)       │             │        │
│   │         └─────────────────────────┘             │        │
│   └─────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Components

| Component | Description |
|-----------|-------------|
| `connection.{hpp,cpp}` | Bidirectional stratum connection with TLS support |
| `event_loop.{hpp,cpp}` | poll() based I/O multiplexing for concurrent connections |
| `pool_manager.{hpp,cpp}` | Pool failover, job caching, share submission |
| `worker_manager.{hpp,cpp}` | Miner connection management, job distribution |
| `stratum.{hpp,cpp}` | JSON-RPC protocol parsing |
| `config.{hpp,cpp}` | JSON configuration loader |

## NixOS Usage

### 1. Configure the proxy

Add to your host configuration:

```nix
services.gpu-proxy-cpp = {
  enable = true;
  listenPort = 3334;

  pools = [
    {
      name = "Kryptex US";
      url = "us.cr29.kryptex.com:7777";
      wallet = "your_wallet_address";
      password = "x";
      tls = true;
      priority = 1;
    }
    {
      name = "Kryptex EU";
      url = "eu.cr29.kryptex.com:7777";
      wallet = "your_wallet_address";
      password = "x";
      tls = true;
      priority = 2;
    }
  ];

  # Optional: worker whitelist (empty = allow all)
  workers = [
    { id = "worker1"; password = ""; }
    { id = "worker2"; password = ""; }
  ];
};
```

### 2. Configure miners

Point your GPU miners to the proxy instead of directly to the pool:

**lolMiner config:**
```
POOL: localhost:3334
WALLET: your_kryptex_wallet
```

### 3. Deploy

```bash
just switch   # or: sudo nixos-rebuild switch --flake .#zephyr
```

## Manual Testing

```bash
# Build manually
cd /etc/nixos/gpu-proxy-cpp/build
cmake .. && make

# Run with config
./gpu-proxy --config /etc/gpu-proxy/config.json
```

## Testing on Zephyr (RTX 3090)

As noted for testing:
1. The RTX 3090 on Zephyr should be used for GPU testing
2. Point lolMiner on Zephyr to the proxy (localhost:3334)
3. Monitor logs for job reception and share submission

## Success Criteria

- ✅ Connects to Kryptex CR29 successfully
- ✅ Receives `mining.notify` messages (jobs)
- ✅ Distributes jobs to connected workers
- ✅ Forwards worker shares to pool
- ✅ Automatic failover to backup pools
- ✅ Non-blocking I/O (multiple concurrent workers)

## Debugging

Logs are written to stderr (captured by journald):

```bash
journalctl -u gpu-proxy-cpp -f
```

Key log messages:
- `[PoolManager] TLS handshake complete` - Connected to pool
- `[PoolManager] Received new job` - Pool sent work
- `[WorkerManager] Accepted connection` - Miner connected
- `[gpu-proxy] Submitting share` - Forwarding worker work to pool

## License

Same as parent NixOS configuration.
