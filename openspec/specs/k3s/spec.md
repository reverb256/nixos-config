# K3s Cluster Specification

## Purpose
This spec describes the K3s Kubernetes cluster topology, ingress, and workload management.

## Requirements

### Requirement: API Server
The K3s API server SHALL be reachable at a stable endpoint.

#### Scenario: API access
- GIVEN a valid kubeconfig
- WHEN connecting to the API server
- THEN the endpoint SHALL be 10.1.1.100:6443
- AND the VIP SHALL route to an available control-plane node

### Requirement: AI Inference Endpoints
Inference endpoints SHALL be stable across pod restarts.

#### Scenario: Inference URLs
- GIVEN the ai-inference namespace is running
- THEN sentry:8001 SHALL serve Qwen3.5-4B
- AND forge:8002 SHALL serve Gemma 4
- AND forge:8003 SHALL serve Qwen3.5-4B (secondary)

### Requirement: MapleSpike Services
MapleSpike services SHALL be available at known endpoints in the maplespike namespace.

#### Scenario: Service URLs
- GIVEN the maplespike namespace is running
- THEN the portal SHALL be at maplespike.lan:31559
- AND the API server SHALL be at maplespike.lan:32481
- AND the MCP server SHALL be at maplespike.lan:31746

### Requirement: Image Registry

#### Scenario: Internal registry
- GIVEN a container image needs to be deployed
- THEN the canonical registry SHALL be nexus:5000
- AND images SHALL be pushed with `--format docker`
- AND tags SHALL be versioned (not just `:latest`)
