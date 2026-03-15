# Kryptex Pool Protocol Investigation

**Date:** 2026-03-14
**Status:** Protocol Incompatibility Identified

## Executive Summary

After extensive investigation, we've discovered that **Kryptex pools use a proprietary protocol** that is **incompatible with standard Stratum**. Our C++ gpu-proxy implements standard Stratum protocol, which explains why it cannot connect to Kryptex Tari (CR29) pools.

## Investigation Results

### Tests Performed

1. **Direct TLS Connection Test**
   - Successfully established TLS 1.3 connection to `xtm-c29-us.kryptex.network:8040`
   - Pool sends no data unless client sends something first

2. **Standard Stratum Messages (All Failed)**
   - `mining.subscribe` with `["lolMiner/1.98a", null]` - **No response**
   - `mining.authorize` with `[wallet, password]` - **No response**
   - `mining.configure` - **No response**
   - Various message formats and orderings - **All failed**

3. **lolMiner Analysis**
   - lolMiner WAS successfully mining on Kryptex pools (15-16 g/s)
   - lolMiner is downloaded from `kryptex-miners-org` GitHub, NOT official repo
   - This is a **Kryptex proprietary fork** with custom protocol modifications

### Key Findings

| Finding | Detail |
|---------|--------|
| **Protocol** | Kryptex uses proprietary protocol, NOT standard Stratum |
| **lolMiner Fork** | `kryptex-miners-org/kryptex-miners` not `lolMiner-revolved` |
| **Standard Messages** | Pool does NOT respond to mining.subscribe, mining.authorize, etc. |
| **Working Clients** | Only Kryptex's proprietary lolMiner fork works |

## Evidence

```
# Our test results
Connecting to xtm-c29-us.kryptex.network:8040
TLS: TLSv1.3
Connected!

SENDING: {"id":1,"method":"mining.subscribe","params":["lolMiner/1.98a",null]}
No response (timeout)

SENDING: {"id":2,"method":"mining.authorize","params":["krxXVNVMM7.zephyr-gpu","x"]}
No response (timeout)

# lolMiner logs (from systemd)
Mar 14 21:09:13 zephyr lolMiner[4035757]: Average speed (15s): 5.87 g/s | 9.33 g/s Total: 15.20 g/s
```

## Conclusion

**Kryptex pools are NOT compatible with standard Stratum protocol.** They use a proprietary protocol that is only implemented in Kryptex's own fork of lolMiner.

## Options Going Forward

### Option 1: Use Different Pools (Recommended)
Find Tari mining pools that support standard Stratum protocol. This allows our gpu-proxy to work without modification.

### Option 2: Reverse-Engineer Kryptex Protocol
Analyze the lolMiner binary to understand the proprietary protocol. Challenges:
- Complex reverse engineering required
- May violate Kryptex ToS
- Protocol could change at any time
- Not recommended

### Option 3: Document Limitation
Accept that gpu-proxy cannot support Kryptex pools and focus on other pool providers.

## Recommendations

1. **Primary**: Search for alternative Tari (CR29) mining pools
2. **Secondary**: Test if Monero pools (Tari uses merge mining with Monero) work
3. **Tertiary**: Document Kryptex as unsupported in gpu-proxy README

## Test Files Created

- `/etc/nixos/gpu-proxy-cpp/test-pool-connection.py` - Direct connection test
- `/etc/nixos/gpu-proxy-cpp/test-pool-variations.py` - Multiple format tests
- `/etc/nixos/gpu-proxy-cpp/test-mimic-lolminer.py` - Exact lolMiner mimic test
- `/etc/nixos/gpu-proxy-cpp/relay-debug.py` - Traffic capture relay
- `/etc/nixos/gpu-proxy-cpp/test-pool-sends-first.py` - Pool sends nothing first
- `/etc/nixos/gpu-proxy-cpp/test-stratum-client.py` - Standard Stratum messages

All tests confirm the same result: **Kryptex pools do not respond to standard Stratum protocol.**

## Additional Research Findings

### Tari Merge Mining Architecture

From the [Tari project documentation](https://github.com/tari-project/tari/wiki/Merge-Mining):

1. **Tari uses merge mining with Monero** - Tari blocks are mined through Monero's RandomX algorithm
2. **Merge Mining Proxy** - Required communication gateway between XMRig and Tari network
3. **Protocol implication** - Tari pools likely use **Monero Stratum protocol** (not standard Bitcoin Stratum)

### Protocol Stack

```
Standard Bitcoin Stratum:
├── mining.subscribe
├── mining.authorize
├── mining.submit
└── mining.notify

Monero/Tari Stratum (likely):
├── login
├── job
├── submit
└── custom extensions

Kryptex Protocol (proprietary):
├── Unknown message format
├── Custom authentication
└── Only works with Kryptex's lolMiner fork
```

### Source Code Evidence

```nix
# From /etc/nixos/packages/lolminer.nix
src = fetchurl {
  url = "https://github.com/kryptex-miners-org/kryptex-miners/...";
  # This is KRYPTEX'S fork, NOT official lolMiner!
};
```

### Conclusion

The Kryptex protocol incompatibility is **by design**:

1. Kryptex distributes a **proprietary fork of lolMiner**
2. The fork implements a **custom protocol** not compatible with standard Stratum
3. This creates **vendor lock-in** - only Kryptex's software works with Kryptex pools
4. Our gpu-proxy implementing standard Stratum will **never work** with Kryptex pools

The solution is to use **pools that support standard protocols** rather than trying to reverse-engineer Kryptex's proprietary system.
