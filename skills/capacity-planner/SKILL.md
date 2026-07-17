---
name: capacity-planner
description: GPU/CPU capacity planning for NixOS AI and mining workloads. Forecast resource needs, balance AI inference vs. mining, and optimize cluster utilization. Use this skill when the user asks about capacity planning, resource forecasting, GPU allocation, scaling AI workloads, or balancing mining with inference.
---

# Capacity Planner - Cluster Resource Forecasting

Plan and optimize GPU/CPU capacity across your NixOS cluster for both AI inference and mining workloads.

## When to Use This Skill

Use this skill when:
- User asks about capacity planning or resource forecasting
- User wants to add AI workloads and needs to know impact on mining
- User asks "how many GPUs do I need?" for AI/training/inference
- User wants to balance mining vs. AI inference
- User needs to scale cluster resources
- User asks about cluster utilization or optimization

## Your Cluster Resources

| Host | GPUs | GPU Type | Current Use Cases |
|------|------|----------|-------------------|
| zephyr | Multi | NVIDIA | Workstation, Gaming, AI, Mining |
| nexus | Multi | NVIDIA | Gaming, VR, Mining, AI |
| forge | Multi | NVIDIA/AMD | Mining, AI |
| sentry | AMD | AMD | Mining |

## Key Concepts

### GPU Resource Types

**Inference Requirements:**
- Small LLM (7B parameters): ~8-16GB VRAM per concurrent user
- Medium LLM (13-34B): ~16-24GB VRAM
- Large LLM (70B): ~40-80GB VRAM (or multi-GPU)
- Image Gen (SDXL): ~8-16GB VRAM

**Mining Requirements:**
- Full GPU utilization (100% power)
- Excludes interactive use during mining
- Can be interrupted/preempted

### Capacity Calculations

```
Effective AI Capacity = Total GPUs - Mining GPUs
Mining Revenue = Mining GPUs × Daily Revenue per GPU
AI Capacity Needed = (Concurrent Users × VRAM per User) / VRAM per GPU
```

## Workflow

### Step 1: Assess Current Capacity

```bash
# Check GPU inventory
nvidia-smi --query-gpu=index,name,memory.total,memory.free --format=csv

# Check current utilization
nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total --format=csv

# List all GPUs in cluster
for host in zephyr nexus forge sentry; do
    echo "=== $host ==="
    ssh "$host.local" 'nvidia-smi -L' 2>/dev/null || echo "No NVIDIA GPUs"
done
```

### Step 2: Forecast AI Needs

Ask the user for:
- **Expected concurrent users** for AI inference
- **Model sizes** they plan to run
- **Peak usage times** (e.g., work hours vs. overnight)
- **Growth projections** (adding users/models in next 3-6 months)

**Quick Reference:**

| Use Case | VRAM Needed | GPUs for 10 Users | GPUs for 50 Users |
|----------|-------------|-------------------|-------------------|
| Chat (7B) | 8GB | 1-2 | 4-6 |
| Chat (13B) | 16GB | 2-3 | 8-12 |
| Chat (34B) | 24GB | 3-4 | 12-16 |
| Image Gen | 16GB | 2-4 | 10-20 |
| Code (70B) | 40GB | 5-8 | 25-40 |

### Step 3: Balance Mining vs AI

**Strategy 1: Time-Based Separation**
- Mine during off-hours (night/weekends)
- AI during work hours
- Typical split: 12h mining / 12h AI

**Strategy 2: Capacity Reservation**
- Reserve specific GPUs for AI
- Others mine 24/7
- Example: 2 GPUs AI + 6 GPUs mining

**Strategy 3: Dynamic Allocation**
- AI priority: preempt mining when needed
- Mining resumes when AI idle
- Best for: bursty AI workloads

### Step 4: Calculate ROI

```
Daily Mining Revenue = (Mining GPUs × $X/day)
AI Value = (User hours × value per hour)
Net Benefit = Mining Revenue + AI Value - Infrastructure Costs
```

### Step 5: Create Capacity Plan

Generate a recommendation:

```bash
#!/usr/bin/env bash
# Capacity planning calculator

TOTAL_GPUS=${1:-8}
AI_USERS=${2:-10}
MODEL_SIZE_GB=${3:-16}  # VRAM per model
CONCURRENCY=${4:-2}     # Users per GPU

# Calculate AI capacity needed
VRAM_NEEDED=$((AI_USERS * MODEL_SIZE_GB))
VRAM_PER_GPU=$((MODEL_SIZE_GB * CONCURRENCY))
AI_GPUS_NEEDED=$((VRAM_NEEDED / VRAM_PER_GPU))

# Round up
if [ $((VRAM_NEEDED % VRAM_PER_GPU)) -ne 0 ]; then
    AI_GPUS_NEEDED=$((AI_GPUS_NEEDED + 1))
fi

MINING_GPUS=$((TOTAL_GPUS - AI_GPUS_NEEDED))

cat <<EOF
=== Capacity Plan ===
Total GPUs: $TOTAL_GPUS
AI Users: $AI_USERS
Model Size: ${MODEL_SIZE_GB}GB

Recommendation:
  AI GPUs: $AI_GPUS_NEEDED
  Mining GPUs: $MINING_GPUS

Utilization:
  AI: $(echo "scale=1; $AI_GPUS_NEEDED * 100 / $TOTAL_GPUS" | bc)%
  Mining: $(echo "scale=1; $MINING_GPUS * 100 / $TOTAL_GPUS" | bc)%

Daily Revenue Impact:
  Mining GPUs: $MINING_GPUS × ~$1/day = ~$((MINING_GPUS))$/day
EOF
```

## Optimization Recommendations

### For AI-Heavy Workloads
- Use quantization (4-bit/8-bit) to reduce VRAM needs
- Implement request queuing for better GPU utilization
- Consider model sharding across multiple GPUs

### For Mining-Heavy Workloads
- Schedule mining during lowest electricity rate hours
- Monitor profitability and auto-shutdown when unprofitable
- Use mining profits to fund AI GPU upgrades

### For Balanced Workloads
- Use LM Studio's queue system for managing AI requests
- Set up preemption: mining pauses when AI request arrives
- Monitor both metrics and adjust balance monthly

## Cluster Scaling

When adding capacity:

1. **Add new host**: Follow your `nixos-deploy` skill for multi-host setup
2. **Add GPUs to existing host**: Update hardware-configuration.nix and rebuild
3. **Optimize software**: Tune model serving (batching, caching)

## Quick Commands

```bash
# Check GPU memory across cluster
for host in $(cat /etc/nixos/hosts); do
    ssh "$host" 'nvidia-smi --query-gpu=memory.free,memory.total --format=csv,noheader'
done

# Estimate capacity needs
/etc/nixos/scripts/calculate-capacity.sh 8 20 16 2

# View current AI load
curl -s http://127.0.0.1:8080/metrics | grep inference

# Check mining status
systemctl status xmrig@* lolminer-*
```

## Seasonal Planning

Consider usage patterns:
- **Work hours (9am-6pm)**: Higher AI demand, pause mining
- **Evenings (6pm-11pm)**: Gaming demand on zephyr/nexus
- **Overnight (11pm-9am)**: Maximum mining, minimal AI
- **Weekends**: Higher gaming, moderate mining

Plan around these patterns for optimal resource utilization.
