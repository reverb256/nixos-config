# Mining Operations Specification

## Purpose
This spec describes revenue-critical GPU mining operations across the cluster.

## Requirements

### Requirement: Mining Continuity
Mining services SHALL run continuously and SHALL NOT be interrupted by cluster operations.

#### Scenario: Deploy safety
- GIVEN a colmena deploy is in progress
- WHEN the deploy affects forge or krash1.5
- THEN the deploy SHALL NOT restart or disable mining services
- AND the mining revenue SHALL be preserved

#### Scenario: Forge mining
- GIVEN forge has 2x RTX 4060 GPUs
- THEN both GPUs SHALL be dedicated to peakminer mining workloads
- AND no other workload SHALL claim these GPUs

#### Scenario: Krash1.5 mining
- GIVEN krash1.5 (10.1.1.151) is a Windows 10 PC
- THEN it SHALL run peakminer via NSSM (Non-Sucking Service Manager)
- AND the krash user SHALL manage the service

### Requirement: Mining Monitoring

#### Scenario: Operator monitoring
- GIVEN a homelab operator
- WHEN checking mining status
- THEN they SHALL use the `miner-audit` skill for parallel health checks
- AND GPU metrics SHALL be verifiable via `nvidia-smi`
