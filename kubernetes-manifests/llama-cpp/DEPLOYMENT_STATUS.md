# llama.cpp Kubernetes Deployment - Status & Next Steps (2026-03-19)

## Current Status: Planning Complete ⏳

### ✅ Completed
1. **Infrastructure Verification**: GPU resources available and working
2. **Manifest Creation**: All Kubernetes manifests created
3. **Model Discovery**: Existing Qwen3.5 models found on Zephyr
4. **Documentation**: Comprehensive README with configuration options

### ⏳ Pending
1. **Image Strategy**: Need to build or source llama.cpp container image
2. **PV/PV Setup**: HostPath PV needs manual creation on Zephyr
3. **Deployment Testing**: Deploy and verify GPU access
4. **Integration**: Update AI Gateway to use Kubernetes service

## Architecture Decision: Image Strategy

### Option 1: Official Image (Recommended)
```yaml
image: ghcr.io/ggerganov/llama.cpp:server-cuda
```
**Pros:**
- Pre-built with CUDA support
- Regularly updated
- Well-tested

**Cons:**
- May not have commit b8419 with Qwen3.5 optimizations
- Larger image size
- May have different CUDA version requirements

### Option 2: Custom NixOS Image
Build from NixOS llama.cpp package:
```nix
# Build on Zephyr
nix-build -A llama-cpp -K

# Create container image
docker load < result
docker tag localhost/llama-cpp <registry>/llama-cpp:b8419
docker push <registry>/llama-cpp:b8419
```

**Pros:**
- Exact commit b8419 with Qwen3.5 support
- Flash Attention + bf16 KV cache guaranteed
- Consistent with NixOS packages

**Cons:**
- Requires image registry setup
- Additional build step
- Maintenance overhead

### Option 3: Host Binary Mount (Fastest for Testing)
Mount NixOS llama.cpp binary directly:
```yaml
volumes:
- name: llama-binary
  hostPath:
    path: /nix/store/...-llama-cpp-.../bin
containers:
volumeMounts:
- name: llama-binary
  mountPath: /usr/local/bin
command: ["/usr/local/bin/llama-server"]
```

**Pros:**
- Uses existing NixOS binary immediately
- No image build required
- Fastest to test

**Cons:**
- Tied to specific Nix store path
- Less portable
- May have library dependency issues

## Recommended Path Forward

### Phase 1: Quick Test (Option 3)
Use host binary mount to test GPU access and model loading:
1. Update deployment with hostPath volume
2. Deploy and verify pod starts
3. Test model loading and inference
4. Verify GPU utilization

### Phase 2: Production Image (Option 1 or 2)
Once testing is successful:
1. If official image works: Use `ghcr.io/ggerganov/llama.cpp:server-cuda`
2. If need custom build: Create NixOS-based image with commit b8419
3. Push to local registry or use `imagePullPolicy: Never`

### Phase 3: Integration
1. Update AI Gateway configuration
2. Test end-to-end inference
3. Monitor performance metrics
4. Document production setup

## Model Inventory

Available models on Zephyr (`/home/j_kro/.lmstudio/models/unsloth/`):

| Model | Size | VRAM Req | Recommended GPU |
|-------|------|----------|-----------------|
| Qwen3.5-0.8B-GGUF | 0.8B | ~1GB | Any NVIDIA |
| Qwen3.5-2B-GGUF | 2B | ~2GB | RTX 3060 Ti/4060 |
| Qwen3.5-4B-GGUF | 4B | ~3GB | RTX 3090/4060 |
| Qwen3.5-9B-GGUF | 9B | ~6GB | RTX 3090 (24GB) |
| Qwen3.5-27B-GGUF | 27B | ~18GB | RTX 3090 (2x GPUs) |

**Current Configuration**: Qwen3.5-2B-IQ4_NL
- Quantized to 4-bit (IQ4_NL)
- Flash Attention enabled
- bf16 KV cache
- NGL 999 (max GPU offloading)
- ~2GB VRAM usage

## Storage Configuration

### Current Setup
```yaml
# PersistentVolume using hostPath
apiVersion: v1
kind: PersistentVolume
metadata:
  name: llama-models-pv
spec:
  capacity:
    storage: 100Gi
  local:
    path: /home/j_kro/.lmstudio/models
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - zephyr
```

### Alternative: NFS Shared Storage
If models need to be accessible from multiple nodes:
```yaml
# Use existing NFS share
nfs:
  server: 10.1.1.120  # nexus
  path: /nfs/nixos-share/models
```

## GPU Scheduling Strategy

### Current: RTX 3090 on Zephyr
```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - zephyr
```

### Future: Multi-GPU Support
For larger models (Qwen3.5-27B):
```yaml
# Request 2 GPUs
resources:
  limits:
    nvidia.com/gpu: "2"

# Or use node selector with GPU count label
nodeSelector:
  nvidia.com/gpu.count: "2"  # Only nodes with 2+ GPUs
```

## Performance Expectations

### Qwen3.5-2B with RTX 3090
- **Model Loading**: ~5 seconds (with NGL 999)
- **Token Generation**: ~80-120 tokens/second
- **VRAM Usage**: ~2GB (IQ4_NL quantization)
- **CPU Usage**: ~200% (2 threads)
- **Power Usage**: ~100W (GPU + CPU)

### Comparison: llama.cpp vs Local Setup
| Metric | Local (systemd) | Kubernetes |
|--------|-----------------|------------|
| GPU Access | Direct | Device Plugin |
| Model Loading | Fast | Same (hostPath PV) |
| Inference Speed | Baseline | Same |
| Scalability | Single node | Cluster-wide |
| Monitoring | Manual | Prometheus |

## Troubleshooting Guide

### Issue: Pod Pending - Insufficient GPUs
**Symptom**: Pod stays in Pending state
**Diagnosis**:
```bash
kubectl describe pod <pod-name> | grep -A 5 "Events:"
# Look for: Insufficient nvidia.com/gpu
```
**Solution**: Check GPU allocation, stop other GPU workloads

### Issue: Model Not Found
**Symptom**: "Failed to load model" in logs
**Diagnosis**:
```bash
kubectl exec -it <pod-name> -- ls -la /models/unsloth/
```
**Solution**: Verify PV mount path and model files exist

### Issue: CUDA Errors
**Symptom**: "CUDA error" or GPU not detected
**Diagnosis**:
```bash
kubectl exec -it <pod-name> -- nvidia-smi
```
**Solution**: Check NVIDIA device plugin, verify GPU resources

### Issue: Slow Inference
**Symptom**: < 10 tokens/second
**Diagnosis**:
```bash
kubectl logs <pod-name> | grep "llama_print_timings"
```
**Solution**: Increase `--threads`, check GPU utilization

## Next Actions

1. **Choose Image Strategy**: Decide between official image vs custom build
2. **Update Deployment**: Modify deployment with chosen image
3. **Create PV Manually**: Ensure hostPath PV is created on Zephyr
4. **Deploy**: Apply manifests and verify pod starts
5. **Test Inference**: Run sample completion and verify output
6. **Monitor**: Check GPU usage and performance metrics
7. **Integrate**: Update AI Gateway to use Kubernetes service
8. **Document**: Update STATUS.md and ROADMAP.md

## Success Criteria

- [ ] Pod schedules successfully on Zephyr with GPU
- [ ] Model loads from /models volume
- [ ] Health endpoint returns 200 OK
- [ ] Inference generates valid responses
- [ ] GPU utilization visible (nvidia-smi)
- [ ] Prometheus metrics accessible
- [ ] AI Gateway can reach service
- [ ] Performance meets expectations (>50 tokens/sec)

## References
- llama.cpp: https://github.com/ggerganov/llama.cpp
- Official Image: https://ghcr.io/ggerganov/llama.cpp
- Qwen Models: https://huggingface.co/Qwen
- Commit b8419: Flash Attention + bf16 KV cache for Qwen3.5
