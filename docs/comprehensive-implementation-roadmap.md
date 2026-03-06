# Comprehensive AI Inference Gateway & Training Platform
## Master Implementation Roadmap

**Last Updated**: 2026-03-05
**Version**: 1.0
**Status**: Complete Planning Phase

---

## Executive Summary

This comprehensive roadmap transforms the AI Inference Gateway into a full-featured **AI Platform** that combines:
1. **Intelligent Model Routing** - Dynamic model selection based on request characteristics
2. **Model Training as a Service** - Cloud-based fine-tuning via Hugging Face Jobs
3. **Comprehensive Observability** - Per-model metrics, distributed tracing
4. **Advanced Caching** - Semantic + exact match caching with compression
5. **Multi-Agent Orchestration** - Specialized agents collaborating on tasks
6. **RAG with URL Ingestion** - Knowledge base population from web sources
7. **Model Conversion Pipeline** - Automated GGUF conversion for local deployment

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     AI Platform Architecture                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    │
│  │   Clients    │───▶│   Gateway    │───▶│   Backends   │    │
│  │              │    │              │    │              │    │
│  │ - OpenAI SDK │    │ - Routing    │    │ - LM Studio  │    │
│  │ - Anthropic  │    │ - Caching    │    │ - ZAI         │    │
│  │ - MCP Tools  │    │ - Training   │    │ - vLLM        │    │
│  │ - Web UI     │    │ - RAG        │    │ - Local       │    │
│  └──────────────┘    │ - Metrics    │    └──────────────┘    │
│                      └──────────────┘                         │
│                           │                                    │
│                           ▼                                    │
│              ┌────────────────────────┐                       │
│              │  Hugging Face Jobs     │                       │
│              │  - Model Training      │                       │
│              │  - Fine-tuning         │                       │
│              │  - GGUF Conversion     │                       │
│              └────────────────────────┘                       │
│                                                                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    │
│  │ Observability│    │   Storage    │    │    Tools     │    │
│  │              │    │              │    │              │    │
│  │ - Prometheus │    │ - Qdrant     │    │ - MCP Broker  │    │
│  │ - Grafana    │    │ - Redis      │    │ - Web Reader  │    │
│  │ - Jaeger     │    │ - HF Hub     │    │ - Validator   │    │
│  │ - Trackio    │    │ - Local      │    │ - Converter   │    │
│  └──────────────┘    └──────────────┘    └──────────────┘    │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Feature Matrix: Current vs Target State

### Current Capabilities (Gateway v2.0)

| Category | Feature | Status | Coverage |
|----------|---------|--------|----------|
| **Routing** | Token-based model selection | ✅ Complete | Basic routing |
| **Metrics** | Per-model request/token tracking | ✅ Complete | All metrics tracked |
| **Observability** | Grafana dashboards | ✅ Complete | Real-time monitoring |
| **RAG** | Document ingestion (text only) | 🟡 Partial | No URL fetching |
| **MCP** | Tool calling, schema listing | 🟡 Partial | No caching |
| **JSON Mode** | response_format support | ❌ Missing | Not implemented |
| **Caching** | Response caching | ❌ Missing | None |
| **Training** | Model fine-tuning | ❌ Missing | None |
| **Conversion** | GGUF format | ❌ Missing | None |
| **Agents** | Multi-agent orchestration | ❌ Missing | None |
| **Resilience** | Retry logic | 🟡 Partial | Limited |
| **Security** | Content moderation, PII | ❌ Missing | None |

### Target Capabilities (Platform v3.0)

| Category | Features | Priority | Est. Time |
|----------|----------|----------|-----------|
| **Compatibility** | JSON Schema mode | ⚡ HIGH | 1h |
| **Resilience** | Exponential backoff retry | ⚡ HIGH | 3h |
| **Performance** | MCP schema caching | ⚡ HIGH | 2h |
| **Performance** | Semantic caching | ⚡ HIGH | 4h |
| **Knowledge** | RAG URL ingestion | ⚡ HIGH | 3h |
| **Security** | PII redaction | ⚡ HIGH | 2h |
| **Security** | Content moderation | ⚡ HIGH | 2h |
| **Training** | SFT/DPO training service | 🚀 MEDIUM | 8h |
| **Training** | Dataset validation | 🚀 MEDIUM | 2h |
| **Training** | Cost estimation | 🚀 MEDIUM | 1h |
| **Deployment** | GGUF conversion | 🚀 MEDIUM | 3h |
| **Orchestration** | Multi-agent routing | 🚀 MEDIUM | 6h |
| **Observability** | Distributed tracing | 🔧 LOW | 5h |
| **Optimization** | Cost tracking | 🔧 LOW | 4h |
| **Optimization** | Prompt compression | 🔧 LOW | 3h |
| **Advanced** | Speculative decoding | 🔧 LOW | 8h |
| **Advanced** | A/B testing | 🔧 LOW | 5h |

**Total Estimated Time**: ~60 hours (1.5 months with 1 developer, 2 weeks with 2-3 developers)

---

## Implementation Phases

### Phase 0: Foundation & Planning (Week 1)

**Goal**: Establish infrastructure, documentation, and workflows

#### Tasks
- [ ] Set up Redis for caching
- [ ] Set up Jaeger for distributed tracing
- [ ] Create NixOS modules for new features
- [ ] Establish testing framework
- [ ] Document all APIs and endpoints
- [ ] Set up CI/CD pipeline
- [ ] Create development environment

**Deliverables**:
- Infrastructure ready (Redis, Jaeger, monitoring)
- Documentation complete
- Test framework established

---

### Phase 0.5: Multi-GPU Architecture Setup ⚡ **NEW**

**Priority**: HIGH
**Estimated**: 7-11 hours
**Owner**: Infrastructure Team
**Status**: Design Complete, Ready for Implementation

**Goal**: Distribute LM Studio across 3 machines (5 GPUs, 56GB VRAM) for optimal Spacebot performance

**Architecture Overview:**
```
                    AI Inference Gateway (zephyr:8080)
                                 │
                ┌────────────────┼────────────────┐
                │                │                │
         Zephyr (32GB)      Forge (16GB)      Nexus (8GB)
         ─────────────      ─────────────      ─────────────
         3090: 24GB         4060 #1: 8GB       3060 Ti: 8GB
         3060 Ti: 8GB       4060 #2: 8GB
         Multi-GPU ✅       Multi-GPU ✅       Single GPU
         75/25 split        50/50 split
```

#### Implementation Tasks

**Step 1: Configure Forge (1-2 hours)**
- [ ] Install LM Studio on forge
- [ ] Configure hardware-config.json (50/50 split)
- [ ] Download qwen3.5-9b-IQ4_NL.gguf (5.1GB)
- [ ] Configure context length (64K), KV cache quantization
- [ ] Enable API server on port 1234
- [ ] Test connectivity from zephyr: `curl http://forge:1234/v1/models`
- [ ] Verify model loading: `nvidia-smi` on forge

**Step 2: Configure Nexus (1-2 hours)**
- [ ] Install LM Studio on nexus
- [ ] Download qwen3.5-4b-IQ4_NL.gguf (2.5GB)
- [ ] Configure context length (32K), KV cache quantization
- [ ] Enable API server on port 1234
- [ ] Test connectivity from zephyr: `curl http://nexus:1234/v1/models`
- [ ] Verify model loading: `nvidia-smi` on nexus

**Step 3: Update Gateway Configuration (2-3 hours)**
- [ ] Create multi-backend NixOS module
- [ ] Update gateway.nix with tier1/tier2/tier3 backends
- [ ] Implement model-to-backend mapping in router.py
- [ ] Add overflow logic for tier2/tier3 models
- [ ] Add health checks for all backends
- [ ] Test gateway rebuild: `sudo nixos-rebuild test`

**Step 4: Testing & Validation (2-3 hours)**
- [ ] Test Cortex → Zephyr (35B, 256K context)
- [ ] Test Workers → Zephyr (27B)
- [ ] Test Channels → Forge (9B, 32K context)
- [ ] Test Compactor → Nexus (4B, 16K context)
- [ ] Measure throughput for each backend
- [ ] Test overflow scenarios (forge full → zephyr)
- [ ] Monitor VRAM usage during peak load
- [ ] Validate failover to Z.ai

**Step 5: Spacebot Integration (1 hour)**
- [ ] Update Spacebot configuration for new routing
- [ ] Test each Spacebot process with gateway
- [ ] Monitor performance metrics
- [ ] Validate end-to-end workflows

#### Model Assignment by Spacebot Process

| Spacebot Process | Primary Model | Context | Backend | Speed | Priority |
|------------------|---------------|---------|---------|-------|----------|
| **Cortex** | qwen3.5-35b-a3b | 256K | Zephyr | 110 t/s | High quality |
| **Workers (complex)** | qwen3.5-35b-a3b | 256K | Zephyr | 110 t/s | Multi-step tasks |
| **Workers (standard)** | qwen3.5-27b | 128K | Zephyr | 150 t/s | Quality + speed |
| **Workers (fast)** | qwen3.5-9b | 64K | Forge | 200 t/s | Quick responses |
| **Channels** | qwen3.5-9b | 32K | Forge | 200 t/s | Interactive |
| **Branches** | qwen3.5-9b-claude-4.6-opus | 64K | Forge | 200 t/s | Reasoning chains |
| **Compactor** | qwen3.5-4b | 16K | Nexus | 300 t/s | Summarization |

#### Expected Performance

| Backend | Model | Context | Speed | Concurrent | Total Throughput |
|---------|-------|---------|-------|------------|------------------|
| **Zephyr** | qwen3.5-35b-a3b | 256K | 110 t/s | 1 | 110 t/s |
| **Zephyr** | qwen3.5-27b | 256K | 150 t/s | 1 | 150 t/s |
| **Forge** | qwen3.5-9b | 64K | 200 t/s | 2 | 400 t/s |
| **Nexus** | qwen3.5-4b | 32K | 300 t/s | 3 | 900 t/s |
| **Total** | - | - | - | - | **~1500 t/s** |

#### Network Configuration

```nix
# /etc/nixos/modules/network/cluster-hosts.nix
services.cluster-hosts = {
  enable = true;
  hosts = {
    "forge" = {
      ip = "192.168.1.100";  # Replace with actual IP
      aliases = ["forge.local"];
    };
    "nexus" = {
      ip = "192.168.1.101";  # Replace with actual IP
      aliases = ["nexus.local"];
    };
    "zephyr" = {
      ip = "127.0.0.1";
      aliases = ["zephyr.local"];
    };
  };
};
```

#### Success Criteria

- [ ] All three LM Studio instances running (zephyr, forge, nexus)
- [ ] All backends reachable from gateway
- [ ] All models loaded and accessible
- [ ] Gateway routing configured correctly
- [ ] Cortex gets 110 t/s with 256K context
- [ ] Channels get 200 t/s with 32K context
- [ ] Compactor gets 300 t/s with 16K context
- [ ] Total throughput > 1000 t/s
- [ ] No backend exceeds 90% VRAM utilization
- [ ] Overflow routing works (forge → zephyr, nexus → forge)
- [ ] Health checks detect backend failures
- [ ] All Spacebot processes route correctly
- [ ] Zero downtime during model swaps

#### Documentation

**Design Document**: `/etc/nixos/docs/plans/2026-03-05-multi-gpu-lmstudio-architecture.md`

**Related Files**:
- Gateway configuration: `modules/services/ai-inference/gateway.nix`
- Router logic: `modules/services/ai-inference/ai_inference_gateway/router.py`
- Cluster hosts: `modules/network/cluster-hosts.nix`

---

### Phase 1: Production Readiness (Weeks 2-3)

**Goal**: Critical features for production deployment

#### 1.1 JSON Schema Mode Compatibility ⚡
**Priority**: HIGH
**Estimated**: 1 hour
**Owner**: Backend Team

**Problem**: OpenAI clients expect `response_format: {type: "json_schema"}` but LM Studio doesn't support it natively.

**Solution**: Transform OpenAI response_format → LM Studio instructions

```python
# In main.py - chat_completions endpoint
async def transform_response_format(body: dict) -> dict:
    """Transform OpenAI response_format to LM Studio instructions."""
    response_format = body.get("response_format", {})

    if not response_format:
        return body

    format_type = response_format.get("type")

    if format_type == "json_object":
        # Simple JSON mode
        system_msg = "You must respond with valid JSON only. No markdown, no code blocks."
        body["messages"].insert(0, {"role": "system", "content": system_msg})

    elif format_type == "json_schema":
        # Structured output with schema
        schema = response_format.get("json_schema", {})
        schema_str = json.dumps(schema, indent=2)

        system_msg = f"""You must respond with valid JSON matching this schema:
{schema_str}

Requirements:
- Respond ONLY with valid JSON
- No markdown code blocks
- No explanations outside the JSON
- All fields from schema must be present"""

        body["messages"].insert(0, {"role": "system", "content": system_msg})

    # Remove response_format from body (LM Studio doesn't use it)
    del body["response_format"]

    return body
```

**API Changes**:
- POST `/v1/chat/completions` - Add response_format transformation
- POST `/v1/chat/completions` - Add JSON validation for json_object responses

**Testing**:
```python
# Test cases
test_json_object_mode()
test_json_schema_mode()
test_text_mode()
test_nested_schema_validation()
```

**Success Criteria**:
- ✅ OpenAI SDK JSON mode works
- ✅ JSON Schema validation passes
- ✅ No breaking changes for text mode

---

#### 1.2 Enhanced Retry with Exponential Backoff ⚡
**Priority**: HIGH
**Estimated**: 3 hours
**Owner**: Backend Team

**Problem**: Limited retry logic, no intelligent backoff, rate limits not handled well.

**Solution**: Implement production-grade retry with tenacity

```python
# In retry_handler.py
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type,
    before_sleep_log
)
import logging

logger = logging.getLogger(__name__)

class RetryableError(Exception):
    """Base class for errors that should trigger retry."""
    pass

class RateLimitError(RetryableError):
    """Rate limit exceeded."""
    pass

class OverloadedError(RetryableError):
    """Service overloaded."""
    pass

class TimeoutError(RetryableError):
    """Request timeout."""
    pass

@retry(
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=1, min=1, max=60),
    retry=retry_if_exception_type(RetryableError),
    before_sleep=before_sleep_log(logger, logging.WARNING),
    reraise=True
)
async def call_backend_with_retry(
    client,
    messages,
    model,
    stream=False,
    max_tokens=None
):
    """Call backend with intelligent retry."""
    # Implementation with rate limit detection
    pass
```

**Configuration** (NixOS):
```nix
retry = {
  max_attempts = mkOption {
    default = 5;
    type = types.int;
  };

  initial_backoff_ms = mkOption {
    default = 1000;
    type = types.int;
  };

  max_backoff_ms = mkOption {
    default = 60000;
    type = types.int;
  };

  jitter_ms = mkOption {
    default = 500;
    type = types.int;
    };
};
```

**Success Criteria**:
- ✅ Exponential backoff (1s → 2s → 4s → 8s → 16s)
- ✅ Jitter to prevent thundering herd
- ✅ Rate limit (429) handled with Retry-After
- ✅ 5xx errors trigger retry
- ✅ Configurable via NixOS

---

#### 1.3 MCP Tool Schema Caching ⚡
**Priority**: HIGH
**Estimated**: 2 hours
**Owner**: Backend Team

**Solution**: Cache MCP tool schemas with TTL

```python
# In mcp_cache.py
class ToolSchemaCache:
    """Cache MCP tool schemas."""

    def __init__(self, default_ttl: int = 300):
        self.cache = {}
        self.ttl = timedelta(seconds=default_ttl)

    async def get_tools(self, server: str, force_refresh: bool = False):
        """Get tools from cache or fetch."""
        cache_key = f"tools:{server}"

        if not force_refresh and cache_key in self.cache:
            cached = self.cache[cache_key]
            if datetime.now() < (cached["cached_at"] + self.ttl):
                return cached["schema"]

        # Fetch from server
        tools = await self._fetch_from_server(server)
        self.cache[cache_key] = {
            "schema": tools,
            "cached_at": datetime.now()
        }
        return tools
```

**Success Criteria**:
- ✅ 5-minute TTL (configurable)
- ✅ Cache HIT returns immediately
- ✅ Cache metrics (hit rate)
- ✅ Manual invalidation endpoint
- ✅ Warm-up on startup

---

### Phase 2: Enhanced Capabilities (Weeks 4-6)

#### 2.1 Semantic Caching with Compression 🚀
**Priority**: HIGH
**Estimated**: 4 hours
**Owner**: Performance Team

**Solution**: Two-layer caching (exact + semantic)

```python
# In semantic_cache.py
class SemanticCache:
    """Two-layer caching: exact match → semantic → backend."""

    def __init__(self, redis_url: str, qdrant_url: str):
        self.exact_cache = ExactMatchCache(redis_url)
        self.semantic_cache = SemanticVectorCache(qdrant_url)
        self.similarity_threshold = 0.95

    async def get_or_fetch(
        self,
        model: str,
        messages: List[Dict],
        backend_callback: Callable
    ) -> str:
        """Try exact cache, then semantic, then fetch."""
        # Implementation...
```

**Success Criteria**:
- ✅ Exact match cache (Redis)
- ✅ Semantic cache (Qdrant, cosine ≥0.95)
- ✅ Cache hit/miss metrics
- ✅ TTL-based invalidation
- ✅ Long prompt compression

---

#### 2.2 RAG URL Ingestion (web-reader) 🚀
**Priority**: HIGH
**Estimated**: 3 hours
**Owner**: RAG Team

**Solution**: Fetch documents from URLs using MCP web-reader

```python
# In url_ingestion.py
class URLIngestionService:
    """Ingest documents from URLs."""

    async def ingest_url(
        self,
        url: str,
        collection: str,
        metadata: Dict
    ) -> Dict:
        """Fetch and ingest URL into RAG."""
        # Implementation with web-reader MCP...
```

**API Endpoints**:
- POST `/v1/rag/ingest_url` - Ingest single URL
- POST `/v1/rag/ingest_urls_batch` - Batch ingestion

**Success Criteria**:
- ✅ Fetch from URLs
- ✅ Prefer MCP web-reader, fallback to HTTP
- ✅ Domain whitelist
- ✅ Batch ingestion (concurrency control)
- ✅ Store source URL in metadata

---

#### 2.3 Request Governance (PII + Moderation) 🚀
**Priority**: HIGH
**Estimated**: 4 hours
**Owner**: Security Team

**Solution**: Content moderation and PII redaction

```python
# In governance.py
class ContentModerator:
    """Filter harmful content."""

    async def moderate_input(self, content: str) -> tuple[bool, str]:
        """Check if content is acceptable."""
        # Block harmful patterns...

class PIIRedactor:
    """Redact personally identifiable information."""

    def redact(self, content: str) -> tuple[str, List[Dict]]:
        """Redact PII from content."""
        # Redact email, SSN, credit card, IP, phone...
```

**Success Criteria**:
- ✅ Block harmful patterns
- ✅ Detect jailbreaks (strict mode)
- ✅ Redact PII (email, SSN, card, IP, phone)
- ✅ Configurable strictness
- ✅ Redaction logging

---

### Phase 3: Model Training Platform (Weeks 7-9)

#### 3.1 Training Service Integration 🚀
**Priority**: MEDIUM
**Estimated**: 6 hours
**Owner**: Training Platform Team

**Solution**: Integrate Hugging Face Jobs for model fine-tuning

**Architecture**:
```
Gateway → Training Service → Hugging Face Jobs → Model Hub → Gateway Deployment
```

**API Endpoints**:
```python
# Submit training job
POST /v1/training/submit
{
  "method": "sft",  # sft, dpo, grpo
  "model": "Qwen/Qwen2.5-0.5B",
  "dataset": "username/dataset",
  "hub_model_id": "username/finetuned-model",
  "config": {
    "num_train_epochs": 3,
    "learning_rate": 2e-4
  }
}

# Check job status
GET /v1/training/jobs/{job_id}

# List training jobs
GET /v1/training/jobs

# Cancel job
DELETE /v1/training/jobs/{job_id}
```

**Implementation**:
```python
# In training_service.py
class TrainingService:
    """Manage model training via Hugging Face Jobs."""

    async def submit_training_job(
        self,
        method: str,
        model: str,
        dataset: str,
        config: dict
    ) -> str:
        """Submit training job to Hugging Face Jobs."""

        script = self._generate_training_script(
            method=method,
            model=model,
            dataset=dataset,
            config=config
        )

        job = hf_jobs("uv", {
            "script": script,
            "flavor": config.get("hardware", "a10g-large"),
            "timeout": config.get("timeout", "4h"),
            "secrets": {"HF_TOKEN": os.environ["HF_TOKEN"]}
        })

        return job["job_id"]

    def _generate_training_script(self, method, model, dataset, config):
        """Generate UV script for training."""

        if method == "sft":
            return f'''
# /// script
# dependencies = ["trl>=0.12.0", "peft>=0.7.0", "trackio"]
# ///

from datasets import load_dataset
from peft import LoraConfig
from trl import SFTTrainer, SFTConfig
import trackio

dataset = load_dataset("{dataset}", split="train")
dataset_split = dataset.train_test_split(test_size=0.1, seed=42)

trainer = SFTTrainer(
    model="{model}",
    train_dataset=dataset_split["train"],
    eval_dataset=dataset_split["test"],
    peft_config=LoraConfig(r=16, lora_alpha=32),
    args=SFTConfig(
        output_dir="training-output",
        push_to_hub=True,
        hub_model_id="{config["hub_model_id"]}",
        num_train_epochs={config.get("num_train_epochs", 3)},
        eval_strategy="steps",
        eval_steps=50,
        report_to="trackio",
        project="{config.get("project", "gateway-training")}",
        run_name="{config.get("run_name", "sft-training")}"
    )
)

trainer.train()
trainer.push_to_hub()
'''
```

**Success Criteria**:
- ✅ Submit SFT/DPO/GRPO jobs
- ✅ Track job status
- ✅ Automatic Hub push
- ✅ Trackio integration
- ✅ Cost estimation

---

#### 3.2 Dataset Validation Service 🚀
**Priority**: MEDIUM
**Estimated**: 2 hours
**Owner**: Training Platform Team

**Solution**: Validate datasets before GPU training

```python
# In dataset_validator.py
class DatasetValidator:
    """Validate dataset format for training."""

    async def validate_dataset(
        self,
        dataset: str,
        method: str,  # sft, dpo, grpo
        split: str = "train"
    ) -> dict:
        """Validate dataset format."""

        # Use dataset inspector MCP tool
        job = hf_jobs("uv", {
            "script": "https://huggingface.co/datasets/mcp-tools/skills/raw/main/dataset_inspector.py",
            "script_args": ["--dataset", dataset, "--split", split]
        })

        # Parse results
        return self._parse_validation_results(job)
```

**API Endpoint**:
```python
POST /v1/training/validate-dataset
{
  "dataset": "username/dataset",
  "method": "dpo",
  "split": "train"
}
```

**Success Criteria**:
- ✅ Validate for SFT/DPO/GRPO
- ✅ Return compatibility status
- ✅ Provide mapping code if needed
- ✅ Fast validation (<1 min)

---

#### 3.3 Cost Estimation Service 🚀
**Priority**: MEDIUM
**Estimated**: 1 hour
**Owner**: Training Platform Team

**Solution**: Estimate training cost before submission

```python
# In cost_estimator.py
class CostEstimator:
    """Estimate training cost and time."""

    async def estimate(
        self,
        model: str,
        dataset: str,
        hardware: str,
        config: dict
    ) -> dict:
        """Estimate cost and time."""

        # Use cost estimation script
        job = hf_jobs("uv", {
            "script": "scripts/estimate_cost.py",
            "script_args": [
                "--model", model,
                "--dataset", dataset,
                "--hardware", hardware,
                "--dataset-size", str(config.get("dataset_size", 1000)),
                "--epochs", str(config.get("num_train_epochs", 3))
            ]
        })

        return job["results"]
```

**Success Criteria**:
- ✅ Estimate time and cost
- ✅ Suggest optimal hardware
- ✅ Recommend timeout

---

#### 3.4 GGUF Conversion Pipeline 🚀
**Priority**: MEDIUM
**Estimated**: 3 hours
**Owner**: Deployment Team

**Solution**: Convert trained models to GGUF format

```python
# In gguf_converter.py
class GGUFConverter:
    """Convert models to GGUF for local deployment."""

    async def convert(
        self,
        model_id: str,
        quantization: str = "q4_k_m",
        output_repo: str = None
    ) -> dict:
        """Convert model to GGUF format."""

        script = self._generate_conversion_script(
            model_id=model_id,
            quantization=quantization,
            output_repo=output_repo
        )

        job = hf_jobs("uv", {
            "script": script,
            "flavor": "a10g-large",
            "timeout": "45m",
            "secrets": {"HF_TOKEN": os.environ["HF_TOKEN"]}
        })

        return job
```

**API Endpoint**:
```python
POST /v1/models/convert-to-gguf
{
  "model_id": "username/my-model",
  "quantization": "q4_k_m",
  "output_repo": "username/my-model-gguf"
}
```

**Success Criteria**:
- ✅ Convert to GGUF format
- ✅ Multiple quantization options
- ✅ Automatic Hub push
- ✅ Support for LoRA adapters

---

### Phase 4: Advanced Orchestration (Weeks 10-11)

#### 4.1 Multi-Agent Orchestration 🚀
**Priority**: MEDIUM
**Estimated**: 6 hours
**Owner**: AI Agents Team

**Solution**: Coordinate multiple specialized agents

```python
# In multi_agent.py
class MultiAgentOrchestrator:
    """Orchestrate multiple specialized agents."""

    async def execute_workflow(
        self,
        workflow: List[AgentTask],
        context: dict
    ) -> dict:
        """Execute multi-agent workflow."""

        # Build dependency graph
        # Execute tasks in topological order
        # Route to specialized agents
        # Aggregate results
```

**Agent Types**:
- **Coding Agent** - Code generation, debugging
- **Research Agent** - Information gathering, analysis
- **Writing Agent** - Content creation
- **Analysis Agent** - Data processing

**Success Criteria**:
- ✅ Multiple agent types
- ✅ Workflow execution
- ✅ Dependency management
- ✅ Result aggregation

---

#### 4.2 Distributed Tracing 🔧
**Priority**: LOW
**Estimated**: 5 hours
**Owner**: Observability Team

**Solution**: End-to-end request tracing with OpenTelemetry

```python
# In tracing.py
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider

# Initialize tracing
tracer = trace.get_tracer(__name__)

# In endpoints
with tracer.start_as_current_span("chat_completion") as span:
    span.set_attribute("model", model)
    # ... routing, backend call, response processing
```

**Success Criteria**:
- ✅ OpenTelemetry integration
- ✅ Jaeger export
- ✅ Trace visualization
- ✅ Performance analysis

---

#### 4.3 Cost Optimization 🔧
**Priority**: LOW
**Estimated**: 4 hours
**Owner**: Platform Team

**Solution**: Track costs and optimize spending

```python
# In cost_optimizer.py
class CostOptimizer:
    """Track and optimize AI costs."""

    async def check_budget(
        self,
        model: str,
        input_tokens: int,
        output_tokens: int
    ) -> tuple[bool, float]:
        """Check if request is within budget."""

        pricing = self.PRICING.get(model, {})
        estimated_cost = self._calculate_cost(
            input_tokens, output_tokens, pricing
        )

        if self.current_spend + estimated_cost > self.monthly_budget:
            return False, estimated_cost

        return True, estimated_cost

    def suggest_degraded_model(self, requested_model: str) -> str:
        """Suggest cheaper alternative."""
        # Cost-based degradation...
```

**Success Criteria**:
- ✅ Per-model pricing
- ✅ Budget tracking
- ✅ Cost alerts
- ✅ Auto-degradation

---

### Phase 5: Advanced Optimization (Week 12)

#### 5.1 Prompt Compression Engine 🔧
**Priority**: LOW
**Estimated**: 3 hours
**Owner**: Performance Team

**Solution**: Optimize prompts to reduce tokens

```python
# In prompt_optimizer.py
class PromptOptimizer:
    """Optimize prompts for efficiency."""

    async def optimize(
        self,
        messages: List[Dict],
        model: str,
        max_tokens: int
    ) -> List[Dict]:
        """Optimize prompt messages."""

        # Remove redundancy
        # Compress system prompt
        # Select optimal examples
```

**Success Criteria**:
- ✅ Token reduction
- ✅ Structure optimization
- ✅ Example selection

---

#### 5.2 A/B Testing Framework 🔧
**Priority**: LOW
**Estimated**: 5 hours
**Owner**: Platform Team

**Solution**: A/B test models for optimization

```python
# In ab_testing.py
class ABTestFramework:
    """A/B test different models."""

    async def route_with_ab_test(
        self,
        messages: List[Dict],
        experiment: str
    ) -> str:
        """Route request based on A/B test."""

        config = await self._get_experiment_config(experiment)
        variant = self._select_variant(config)

        await self._track_impression(experiment, variant)
        return variant.model
```

**Success Criteria**:
- ✅ Experiment configuration
- ✅ Variant selection
- ✅ Conversion tracking
- ✅ Statistical analysis

---

#### 5.3 Speculative Decoding Integration 🔧
**Priority**: LOW
**Estimated**: 8 hours
**Owner**: Performance Team

**Solution**: Use draft models for 2-3x speedup

```python
# In speculative_decoding.py
class SpeculativeDecoder:
    """Use small draft model to predict tokens."""

    async def generate_with_speculation(
        self,
        prompt: str,
        target_model: str,
        draft_model: str
    ) -> str:
        """Generate using speculative decoding."""

        # 1. Draft model predicts tokens
        # 2. Target model verifies
        # 3. Accept verified tokens
        # 4. Continue normally
```

**Success Criteria**:
- ✅ 2-3x latency reduction
- ✅ Draft model selection
- ✅ Acceptance rate tracking
- ✅ KV cache optimization

---

## Infrastructure Requirements

### New Services

```nix
# In hardware-configuration.nix
services = {
  # Redis for caching
  redis = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
    maxmemory = "2gb";
    save = [];
  };

  # Jaeger for tracing
  jaeger = {
    enable = true;
    agent = {
      enable = true;
      host = "127.0.0.1";
      port = 6831;
    };
  };

  # Qdrant for semantic cache
  qdrant = {
    enable = true;
    port = 6333;
  };
};
```

### Python Dependencies

```python
# requirements.txt additions

# Phase 1
tenacity>=8.2.0           # Retry with exponential backoff
redis>=5.0.0              # Exact match caching

# Phase 2
beautifulsoup4>=4.12.0    # HTML parsing
qdrant-client>=1.7.0      # Vector DB for semantic cache
opentelemetry-api>=1.22.0  # Distributed tracing
opentelemetry-sdk>=1.22.0  # Distributed tracing
opentelemetry-exporter-jaeger>=1.21.0

# Phase 3
# (Hugging Face Jobs handles training dependencies)

# Phase 4
# (No new dependencies for orchestration)

# Phase 5
# (No new dependencies for optimization)
```

---

## API Reference

### Existing Endpoints (v2.0)

```
POST /v1/chat/completions    # Chat with streaming
POST /v1/messages              # Anthropic compatibility
GET  /v1/models                # List available models
GET  /health                    # Health check
GET  /metrics                   # Prometheus metrics
GET  /mcp/servers              # List MCP servers
GET  /mcp/tools                # List MCP tools
POST /mcp/tools/:name          # Call MCP tool
```

### New Endpoints (v3.0)

```
# Training Service
POST /v1/training/submit                 # Submit training job
GET  /v1/training/jobs/{job_id}         # Get job status
GET  /v1/training/jobs                    # List all jobs
DELETE /v1/training/jobs/{job_id}      # Cancel job
POST /v1/training/validate-dataset      # Validate dataset
POST /v1/training/estimate-cost         # Estimate cost

# RAG Enhancement
POST /v1/rag/ingest_url                 # Ingest single URL
POST /v1/rag/ingest_urls_batch          # Batch ingest URLs
POST /v1/rag/search                     # Semantic search

# Model Conversion
POST /v1/models/convert-to-gguf          # Convert to GGUF
GET  /v1/models/conversions/{job_id}    # Get conversion status

# Multi-Agent
POST /v1/agents/execute                 # Execute agent task
POST /v1/agents/workflow                 # Execute workflow
GET  /v1/agents                          # List agents

# Cost & Governance
GET  /v1/cost/current-month              # Current month spend
GET  /v1/cost/forecast                   # Cost forecast
POST /v1/governance/scan                 # Scan content for PII
```

---

## Configuration Management

### Gateway Configuration (NixOS)

```nix
# modules/services/ai-inference/default.nix

{ config, lib, ... }:

{
  options = {
    # === Core Gateway ===
    gateway_host = mkOption {
      default = "0.0.0.0";
      type = types.str;
      description = "Gateway bind address";
    };

    gateway_port = mkOption {
      default = 8080;
      type = types.int;
      description = "Gateway port";
    };

    # === Backends ===
    backend_url = mkOption {
      default = "http://127.0.0.1:1234/v1";
      type = types.str;
      description = "Primary LM Studio backend";
    };

    fallback_backends = mkOption {
      default = [];
      type = types.listOf types.str;
      description = "Fallback backend URLs";
    };

    # === Routing ===
    routing = {
      enable = mkOption {
        default = true;
        type = types.bool;
      };

      default_model = mkOption {
        default = "qwen/qwen3.5-9b";
        type = types.str;
      };

      rules = mkOption {
        default = [];
        type = types.listOf (types.submodule [{ rules = [...] }]);
        description = "Model routing rules";
      };
    };

    # === Caching ===
    caching = {
      enable = mkOption {
        default = true;
        type = types.bool;
      };

      exact_match = {
        enable = mkOption {
          default = true;
          type = types.bool;
        };
        ttl_seconds = mkOption {
          default = 3600;
          type = types.int;
        };
      };

      semantic = {
        enable = mkOption {
          default = true;
          type = types.bool;
        };
        similarity_threshold = mkOption {
          default = 0.95;
          type = types.float;
        };
      };
    };

    # === MCP ===
    mcp = {
      enable = mkOption {
        default = false;
        type = types.bool;
      };

      cache_ttl_seconds = mkOption {
        default = 300;
        type = types.int;
      };

      warmup_on_startup = mkOption {
        default = true;
        type = types.bool;
      };
    };

    # === Training ===
    training = {
      enable = mkOption {
        default = false;
        type = types.bool;
        description = "Enable training service";
      };

      hf_token = mkOption {
        default = null;
        type = types.nullOr types.str;
        description = "Hugging Face token for Jobs";
      };

      default_hardware = mkOption {
        default = "a10g-large";
        type = types.str;
        description = "Default hardware for training";
      };
    };

    # === RAG ===
    rag = {
      enable = mkOption {
        default = false;
        type = types.bool;
      };

      ingestion = {
        enable = mkOption {
          default = false;
          type = types.bool;
        };
        allowed_domains = mkOption {
          default = null;
          type = types.nullOr (types.listOf types.str);
        };
        max_concurrent = mkOption {
          default = 5;
          type = types.int;
        };
      };
    };

    # === Security ===
    security = {
      content_moderation = {
        enable = mkOption {
          default = true;
          type = types.bool;
        };
        strict_mode = mkOption {
          default = false;
          type = types.bool;
        };
      };

      pii_redaction = {
        enable = mkOption {
          default = true;
          type = types.bool;
        };
        redact_user_input = mkOption {
          default = true;
          type = types.bool;
        };
        redact_model_output = mkOption {
          default = false;
          type = types.bool;
        };
      };
    };

    # === Observability ===
    observability = {
      prometheus = {
        enable = mkOption {
          default = true;
          type = types.bool;
        };
        port = mkOption {
          default = 9190;
          type = types.int;
        };
      };

      jaeger = {
        enable = mkOption {
          default = false;
          type = types.bool;
        };
        agent_host = mkOption {
          default = "127.0.0.1";
          type = types.str;
        };
        agent_port = mkOption {
          default = 6831;
          type = types.int;
        };
      };

      trackio = {
        enable = mkOption {
          default = true;
          type = types.bool;
        };
        space_id = mkOption {
          default = null;
          type = types.nullOr types.str;
        };
      };
    };

    # === Cost Management ===
    cost = {
      enable = mkOption {
        default = false;
        type = types.bool;
      };

      monthly_budget_usd = mkOption {
        default = 100.0;
        type = types.float;
      };

      alert_threshold = mkOption {
        default = 0.8;
        type = types.float;
        description = "Alert at X% of budget";
      };

      auto_degrade = mkOption {
        default = false;
        type = types.bool;
        description = "Auto-switch to cheaper models at budget limit";
      };
    };
  };
}
```

---

## Success Metrics

### Phase 1 Success Criteria
- [ ] JSON mode compatibility with OpenAI SDK
- [ ] <1% failure rate with retry logic
- [ ] 90%+ cache hit rate for repeated MCP queries
- [ ] All PII types redacted with 99%+ accuracy
- [ ] Content moderation blocks 100% of harmful patterns

### Phase 2 Success Criteria
- [ ] 40%+ exact match cache hit rate
- [ ] 20%+ semantic cache hit rate
- [ ] <5 second average URL ingestion
- [ ] Distributed tracing end-to-end
- [ ] Cost tracking within 5% accuracy

### Phase 3 Success Criteria
- [ ] Training service operational
- [ ] 10+ successful SFT/DPO jobs
- [ ] 5+ successful GGUF conversions
- [ ] Dataset validation prevents 95%+ format errors
- [ ] Cost estimation within 20% accuracy

### Phase 4 Success Criteria
- [ ] Multi-agent workflows operational
- [ ] 3+ agent types available
- [ ] Speculative decoding achieves 2x speedup
- [ ] A/B testing framework deployed

---

## Risk Assessment

| Feature | Risk | Probability | Impact | Mitigation |
|---------|------|------------|-------|------------|
| JSON mode | LM Studio may not follow instructions | Medium | High | Add validation, fallback |
| Retry | Long waits on failures | Low | Medium | Max timeout, user feedback |
| Semantic cache | False positives | Low | Medium | High threshold (0.95+) |
| URL ingest | Malicious URLs | Medium | High | Domain whitelist, size limits |
| Training | Cost overruns | Medium | High | Cost caps, estimation |
| GGUF | Conversion failures | Low | Medium | Validation, fallback |

---

## Testing Strategy

### Unit Tests
```bash
# Test individual components
pytest tests/unit/test_response_format.py
pytest tests/unit/test_retry.py
pytest tests/unit/test_cache.py
pytest tests/unit/test_moderation.py
```

### Integration Tests
```bash
# Test component interactions
pytest tests/integration/test_training_workflow.py
pytest tests/integration/test_rag_ingestion.py
pytest tests/integration/test_multi_agent.py
```

### Load Tests
```bash
# Test performance under load
locust --host=http://127.0.0.1:8080 --users=100 --spawn-rate=10
```

### End-to-End Tests
```bash
# Test complete workflows
pytest tests/e2e/test_json_mode_e2e.py
pytest tests/e2e/test_training_to_deployment.py
```

---

## Rollout Plan

### Week 1: Foundation
1. Set up infrastructure (Redis, Jaeger, Qdrant)
2. Configure NixOS modules
3. Set up monitoring
4. Create test framework

### Week 2-3: Phase 1 (Production Readiness)
1. Implement JSON mode
2. Implement retry logic
3. Implement MCP caching
4. Test and validate

### Week 4-6: Phase 2 (Enhanced Capabilities)
1. Implement semantic caching
2. Implement URL ingestion
3. Implement content governance
4. Load testing and optimization

### Week 7-9: Phase 3 (Training Platform)
1. Integrate Hugging Face Jobs
2. Implement dataset validation
3. Implement cost estimation
4. Implement GGUF conversion
5. Test training workflows

### Week 10-11: Phase 4 (Orchestration)
1. Implement multi-agent system
2. Implement distributed tracing
3. Implement cost optimization
4. Integration testing

### Week 12: Phase 5 (Optimization)
1. Implement prompt compression
2. Implement A/B testing
3. Implement speculative decoding
4. Performance tuning
5. Documentation

---

## Documentation Requirements

### User Documentation
- [ ] API reference (all endpoints)
- [ ] Configuration guide
- [ ] Quick start guide
- [ ] Tutorial examples
- [ ] Troubleshooting guide

### Developer Documentation
- [ ] Architecture overview
- [ ] Code organization
- [ ] Contributing guide
- [ ] Testing guide
- [ ] Deployment guide

### Operator Documentation
- [ ] Installation guide
- [ ] Configuration reference
- [ ] Monitoring guide
- [ ] Runbook for incidents
- [ ] Capacity planning

---

## Next Steps

1. **Review and approve roadmap** - Get stakeholder alignment
2. **Prioritize based on needs** - Select features for immediate implementation
3. **Set up infrastructure** - Prepare Redis, Jaeger, Qdrant
4. **Begin Phase 1** - Start with production readiness features
5. **Establish metrics** - Track progress and success criteria

---

## Conclusion

This comprehensive roadmap transforms the AI Inference Gateway into a full-featured **AI Platform** that combines:
- Intelligent routing and caching
- Model training and fine-tuning
- Multi-agent orchestration
- Comprehensive observability
- Production-grade reliability

**Total estimated effort**: ~60 hours (1.5 months solo, 2 weeks with 2-3 developers)

**Recommended starting point**: Phase 1 (Production Readiness) for immediate production deployment.

---

**Sources**:
- [Hugging Face TRL Jobs](https://huggingface.co/docs/trl/en/jobs_training)
- [Hugging Face Jobs Documentation](https://huggingface.co/docs/huggingface_hub/guides/jobs)
- [Portkey AI Gateway](https://portkey.ai/docs/gateway-capabilities)
- [Semantic Caching Research](https://arxiv.org/html/2601.06007v2)
- [Speculative Decoding](https://arxiv.org/abs/2305.10442)
- [OpenAI Structured Outputs](https://platform.openai.com/docs/guides/structured-outputs)
