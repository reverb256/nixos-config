# Cluster Architecture Specification

## Purpose
This spec describes the homelab cluster topology — node roles, networking, and service assignments.

## Requirements

### Requirement: Control Plane Topology
The cluster SHALL have three control-plane nodes for quorum.

#### Scenario: Control plane nodes
- GIVEN the cluster is fully operational
- THEN zephyr, sentry, and nexus SHALL serve as K3s server nodes
- AND the VIP SHALL be at 10.1.1.100

#### Scenario: Control plane failure tolerance
- GIVEN one control-plane node is offline
- THEN the cluster SHALL continue serving workloads
- AND no new pods SHALL be scheduled to the failed node

### Requirement: Worker Node GPU Allocation
Worker nodes SHALL be assigned to specific GPU workloads.

#### Scenario: Forge GPU allocation
- GIVEN the forge node has 2x NVIDIA RTX 4060 GPUs
- THEN they SHALL be dedicated to mining workloads
- AND inference workloads SHALL NOT preempt mining GPU allocation

#### Scenario: Zephyr GPU allocation
- GIVEN zephyr has an RTX 4090 and RTX 3090
- THEN the 4090 SHALL serve AI inference (sentry:8001, forge:8002, forge:8003)
- AND the 3090 SHALL serve TTS (chatterbox) and AI image generation

### Requirement: Node Roles

#### Scenario: Zephyr role
- GIVEN zephyr (10.1.1.110) is the primary control node
- THEN it SHALL run Niri (Wayland) desktop
- AND ALL NixOS config SHALL originate from /etc/nixos on zephyr
- AND it SHALL be the K3s server + gateway host

#### Scenario: Haven role
- GIVEN haven is the infrastructure services node
- THEN it SHALL host non-GPU auxiliary services

#### Scenario: Krash3 role
- GIVEN krash3 (10.1.1.150) is the KVM hypervisor
- THEN it SHALL host krash3-vm (Windows 11 with RTX 4060 passthrough)
- AND krash3-vm SHALL use libvirt/QEMU, NOT KubeVirt

### Requirement: Config Management

#### Scenario: Declarative config
- GIVEN a change is needed on any cluster node
- THEN the change SHALL be made in /etc/nixos on zephyr
- AND committed with `git add -A && git commit`
- AND deployed with `colmena deploy`
- AND imperative changes on target hosts SHALL NOT be made

#### Scenario: Deploy safety
- GIVEN a deploy to revenue-critical nodes (forge, krash1.5)
- THEN mining services SHALL NOT be disabled
- AND the rollback plan SHALL be `git revert + git push + colmena deploy`
