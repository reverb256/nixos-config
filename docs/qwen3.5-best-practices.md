# Qwen3.5 Model Best Practices

**Last Updated**: 2026-03-05
**Platform**: LM Studio / llama.cpp
**Purpose**: Optimal configuration for each Qwen3.5 variant

---

## Overview

Qwen3.5 models require different configurations based on size, quantization, and intended use case. This guide provides production-tested defaults for each model variant.

## Universal Settings (All Models)

```python
# Enable for all Qwen3.5 models
{
    "thinking_mode": True,        # Enable reasoning capabilities
    "max_output_tokens": 32768,   # 32K+ output for complex tasks
    "flash_attention": True,      # Faster inference
    "full_gpu_offload": True,     # Complete model on GPU
}
```

---

## Vision Support

**Vision-Capable Models** (have `mmproj` files):
- ✅ **qwen3.5-35b-a3b** (mmproj-F32.gguf) - Best quality, 256K context
- ✅ **qwen3.5-27b** (mmproj-F32.gguf) - High quality
- ✅ **qwen3.5-9b** (mmproj-F32.gguf) - Balanced
- ✅ **qwen3.5-4b** (mmproj-F32.gguf) - Fast
- ✅ **crow-9b-opus-4.6-distill-heretic_qwen3.5** (mmproj-f16.gguf)

**Vision Temperature Guidelines**:
- **0.8B/2B**: 0.7 (more conservative for vision)
- **4B+**: Use standard temperature (0.6-1.0)
- Vision requires more deterministic outputs than text

**OpenAI API Format** (Multimodal Messages):
```python
# Include images in message content
messages = [
    {
        "role": "user",
        "content": [
            {
                "type": "text",
                "text": "What's in this image?"
            },
            {
                "type": "image_url",
                "image_url": {
                    "url": "data:image/jpeg;base64,/9j/4AAQSkZJRg..."  # or HTTP URL
                }
            }
        ]
    }
]
```

**Gateway Auto-Routing**:
```python
# Gateway automatically detects vision and routes to capable models
# Vision tasks automatically prioritize vision-capable models
# Quality priority → 35B-A3B (best understanding)
# Speed priority → 4B (fastest response)
```

**Best Practices**:
- Use base64 encoding for local images (`data:image/...;base64,...`)
- Use HTTP URLs for remote images (gateway will fetch)
- Lower temperature for vision (0.7 for 0.8B/2B)
- Vision doesn't benefit from long context (8-16K sufficient)

**Example Request**:
```bash
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5-9b",
    "messages": [
      {
        "role": "user",
        "content": [
          {"type": "text", "text": "Describe this image."},
          {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,..."}}
        ]
      }
    ],
    "max_tokens": 100
  }'
```

---

## Model-Specific Configurations

### 0.8B / 2B Models

**Use Case**: Edge devices, basic tasks, simple Q&A

**Recommended Quantization**: `IQ4_NL` or `Q8_0`

**Parameters**:
```python
{
    "temperature": 1.0,          # Higher temperature for text
    "top_p": 0.95,               # Full nucleus sampling
    "context_length": 8192,      # 8K context (32K max)
}
```

**Vision Tasks**:
```python
{
    "temperature": 0.7,          # Lower temperature for vision
    "top_p": 1.0,                # Deterministic vision outputs
    "context_length": 8192,      # Vision doesn't need long context
}
```

**Avoid**:
- ❌ Few-shot prompting on code tasks (too small for code reasoning)
- ❌ Complex chain-of-thought (lacks reasoning depth)

**Ideal For**:
- ✅ Simple chatbots
- ✅ Basic question answering
- ✅ Edge deployment (Raspberry Pi, mobile)
- ✅ Quick prototyping

---

### 4B Model

**Use Case**: Multimodal agents, modest GPUs (8GB VRAM)

**Recommended Quantization**: `Q4_K_S` or `IQ4_NL`

**Parameters**:
```python
{
    "temperature": 0.6,          # Lower for focused responses
    "top_p": 0.95,               # Standard nucleus sampling
    "context_length": 32768,     # 32K context
}
```

**Ideal For**:
- ✅ Multimodal agents (vision + text)
- ✅ General-purpose chat
- ✅ GPUs with 8GB VRAM
- ✅ Balanced quality/speed

**Performance**:
- **Speed**: ~300 tokens/sec on RTX 3060 Ti
- **Memory**: ~5GB VRAM with Q4_K_S
- **Context**: Up to 32K tokens

---

### 9B Models (Base + Distilled Variants)

**Variants**:
- `qwen3.5-9b` (base)
- `qwen3.5-9b-claude-4.6-opus-distilled-32k`
- `crow-9b-opus-4.6-distill-heretic_qwen3.5` (Jackrong's distill)

**Use Case**: General reasoning, Chain-of-Thought, structured tasks

**Recommended Quantization**: `IQ4_NL` or `Q4_K_S`

**Parameters**:
```python
{
    "temperature": 0.6,          # Lower for reasoning
    "top_p": 0.95,               # Focused sampling
    "context_length": 32768,     # 32K (128K max with quantization)
}
```

**Chain-of-Thought Prompting**:
```python
# Use <think> tags for reasoning
prompt = """


Now provide your response:
"""
```

**For Distilled Variants (Claude-style)**:
```python
# Use Claude-style prompts
prompt = """
Please analyze this task carefully:
- What are the key requirements?
- What approach would be best?
- What are the potential issues?

Then provide your solution.
"""
```

**Ideal For**:
- ✅ Chain-of-thought reasoning
- ✅ Structured output (JSON, code)
- ✅ Multi-step problem solving
- ✅ Code generation and debugging
- ✅ General-purpose assistance

**Performance**:
- **Speed**: ~200 tokens/sec on RTX 4060
- **Memory**: ~6GB VRAM with IQ4_NL
- **Context**: Up to 128K tokens with KV cache quantization

---

### 27B Model

**Use Case**: Dense quality priority, complex tasks

**Recommended Quantization**: `Q4_K_M` or `IQ4_NL`

**Parameters**:
```python
{
    "temperature": 0.6,          # Lower for consistency
    "top_p": 0.95,               # Focused sampling
    "context_length": 262144,    # 256K context (with KV cache)
}
```

**Ideal For**:
- ✅ High-quality text generation
- ✅ Complex reasoning tasks
- ✅ Long-context understanding
- ✅ Professional/enterprise applications

**Performance**:
- **Speed**: ~150 tokens/sec on RTX 3090
- **Memory**: ~18GB VRAM with Q4_K_M
- **Context**: Full 256K with quantized KV cache

---

### 35B-A3B (Mixture-of-Experts)

**Model**: `qwen3.5-35b-a3b`

**Use Case**: Maximum quality with long context, Cortex workloads

**Recommended Quantization**: `Q4_0` for KV cache only

**Parameters**:
```python
{
    "temperature": 0.6,          # Lower for consistency
    "top_p": 0.95,               # Focused sampling
    "context_length": 262144,    # 256K context (optimal)
}
```

**Special Configuration**:
```python
# KV Cache Quantization (CRITICAL for 256K context)
{
    "kv_cache_quantization": "Q4_0",  # Enable KV cache quantization
    "flash_attention": True,           # Required for speed
}
```

**Why 35B-A3B over 27B**:
- ✅ Faster (~110 t/s vs 150 t/s on 3090, but better quality)
- ✅ Mixture-of-Experts architecture
- ✅ Superior long-context performance
- ✅ Better for complex reasoning

**Ideal For**:
- ✅ **Cortex** (primary use case)
- ✅ Long-document analysis (256K context)
- ✅ Complex multi-step reasoning
- ✅ High-quality professional content
- ✅ Research and analysis

**Performance**:
- **Speed**: ~110 tokens/sec on RTX 3090 (llama.cpp)
- **Memory**: ~24GB VRAM (3090) + 8GB VRAM (3060 Ti) with split
- **Context**: Full 256K with Q4_0 KV cache
- **Quality**: Superior to 27B dense despite similar speed

---

## Quantization Guide

### Quantization Types

| Quantization | VRAM Savings | Quality Loss | Best For |
|-------------|--------------|--------------|----------|
| **Q8_0** | Minimal | None | Maximum quality |
| **Q6_K** | ~25% | Negligible | Balance |
| **Q4_K_M** | ~50% | Minimal | General use |
| **Q4_K_S** | ~50% | Small | Speed priority |
| **IQ4_NL** | ~50% | Small | Optimized for 4B-9B |
| **Q4_0** | ~50% | Small | KV cache only |

### When to Use Each

**Q8_0**:
- Maximum quality required
- Ample VRAM available
- Small models (0.8B-2B)

**Q4_K_M**:
- Best balance of quality/size
- 27B model on 24GB VRAM
- General production use

**Q4_K_S**:
- Speed priority
- 9B model on 8GB VRAM
- 4B model on 6GB VRAM

**IQ4_NL**:
- Optimized for mid-range models (4B-9B)
- Better quality than standard Q4
- Recommended for 4B and 9B

**Q4_0** (KV Cache Only):
- **Never use for model weights**
- Only for KV cache quantization
- Enables 256K context on 32GB VRAM

---

## Context Length Strategy

### Short Context (8-16K)
**Models**: 0.8B, 2B, 4B
**Use Cases**:
- Simple chat
- Short-form content
- Quick tasks

### Medium Context (32-128K)
**Models**: 4B, 9B, 27B
**Use Cases**:
- Document analysis
- Multi-turn conversations
- Code generation

### Long Context (256K)
**Models**: 27B, 35B-A3B
**Requirements**:
- KV cache quantization (Q4_0)
- 32GB+ VRAM (35B-A3B)
- Flash attention enabled

**Use Cases**:
- **Cortex** (primary)
- Long-document analysis
- Book-length content
- Complex multi-document reasoning

---

## Spacebot Process Assignments (Zephyr)

### Cortex
**Model**: `qwen3.5-35b-a3b`
**Context**: 256K
**Speed**: ~110 t/s
**VRAM**: 32GB (3090 + 3060 Ti split)
**Temperature**: 0.6
**Purpose**: Complex reasoning, long context

### Workers
**Model**: `qwen3.5-9b`
**Context**: 32K
**Speed**: ~200 t/s
**VRAM**: 16GB (2x RTX 4060 on forge)
**Temperature**: 0.6-0.8
**Purpose**: General task processing

### Channels
**Model**: `qwen3.5-4b`
**Context**: 32K
**Speed**: ~300 t/s
**VRAM**: 8GB (RTX 3060 Ti on nexus)
**Temperature**: 0.7-1.0
**Purpose**: Fast responses, simple tasks

### Compactor
**Model**: `qwen3.5-4b`
**Context**: 16K
**Speed**: ~300 t/s
**VRAM**: 8GB (RTX 3060 Ti on nexus)
**Temperature**: 0.7
**Purpose**: Summarization, compression

### Branches
**Model**: `qwen3.5-9b`
**Context**: 64K
**Speed**: ~200 t/s
**VRAM**: 16GB (2x RTX 4060 on forge)
**Temperature**: 0.6-0.8
**Purpose**: Forked reasoning tasks

---

## Prompting Strategies

### Chain-of-Thought (9B+ distilled)

```python
cot_prompt = """
<think>
I need to solve this step by step:

Step 1: Understand the problem
{problem_analysis}

Step 2: Identify key constraints
{constraints}

Step 3: Generate possible solutions
{solutions}

Step 4: Evaluate and select best
{evaluation}

Step 5: Final answer
{final_answer}
</think>

Based on my analysis, here's my response:
"""
```

### Claude-Style (Distilled Variants)

```python
claude_prompt = """
Let me carefully analyze this request:

**Understanding**: What is being asked?
{understanding}

**Approach**: How should I tackle this?
{approach}

**Considerations**: What should I keep in mind?
{considerations}

**Solution**: What is my answer?
{solution}
"""
```

### Direct (Small Models)

```python
simple_prompt = """
{task}

Please provide a clear, concise response.
"""
```

---

## Performance Optimization

### llama.cpp Flags

```bash
# For 35B-A3B with 256K context
./llama-cli \
  --model qwen3.5-35b-a3b.Q4_K_M.gguf \
  --gpu-layers 999 \
  --ctx-size 262144 \
  --flash-attn \
  --kv-cache-type f16 \
  --temp 0.6 \
  --top-p 0.95

# For 9B with 32K context
./llama-cli \
  --model qwen3.5-9b.IQ4_NL.gguf \
  --gpu-layers 999 \
  --ctx-size 32768 \
  --flash-attn \
  --temp 0.6 \
  --top-p 0.95
```

### LM Studio Settings

**35B-A3B**:
- GPU Layers: All (split across GPUs if needed)
- Context Length: 262144
- Batch Size: 512
- KV Cache Quantization: Q4_0
- Flash Attention: ✅ Enabled
- Thread Count: CPU cores

**9B**:
- GPU Layers: All
- Context Length: 32768
- Batch Size: 512
- Flash Attention: ✅ Enabled

**4B**:
- GPU Layers: All
- Context Length: 32768
- Batch Size: 512
- Flash Attention: ✅ Enabled

---

## Troubleshooting

### Out of Memory Errors

**Symptom**: `CUDA out of memory`

**Solutions**:
1. Reduce context length
2. Use smaller quantization (Q4_K_S instead of Q4_K_M)
3. Enable KV cache quantization (Q4_0)
4. Split model across multiple GPUs

### Slow Inference

**Symptom**: <50 tokens/sec

**Solutions**:
1. Verify GPU offload (`--gpu-layers 999`)
2. Enable flash attention
3. Increase batch size (512 → 1024)
4. Use smaller model if quality acceptable

### Poor Quality

**Symptom**: Incoherent or irrelevant responses

**Solutions**:
1. Lower temperature (1.0 → 0.6)
2. Enable thinking mode
3. Use larger model (upgrade from 4B → 9B)
4. Improve prompt (add structure, examples)

### Context Not Utilized

**Symptom**: Model ignores early conversation

**Solutions**:
1. Verify context length setting
2. Check KV cache quantization is enabled
3. Use model with larger context (9B → 27B → 35B-A3B)

---

## References

- **Qwen3.5 Models**: https://huggingface.co/Qwen
- **llama.cpp**: https://github.com/ggerganov/llama.cpp
- **LM Studio**: https://lmstudio.ai/
- **Quantization Guide**: https://github.com/ggerganov/llama.cpp/blob/master/examples/quantize/README.md

---

## Changelog

**2026-03-05**:
- Initial documentation
- Added 35B-A3B configuration for Cortex
- Documented Spacebot process assignments
- Added quantization guide
- Added troubleshooting section
