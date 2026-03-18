# SearXNG AI/LLM Integration Patterns Research

**Date:** 2026-03-17
**Method:** Used working SearXNG integration to search for AI-specific implementations

---

## 🔍 **RESEARCH FINDINGS**

### **Pattern 1: MCP Server Integration**

**Project:** [tisDDM/searxng-mcp](https://github.com/tisddm/searxng-mcp)

**Description:** Model Context Protocol (MCP) server for SearXNG

**Key Features:**
- MCP-compliant server for SearXNG
- Integrates with Smolagents AI framework
- Enables research agents with web search capabilities
- Similar pattern to our implementation

**Implementation Notes:**
```
- SearXNG acts as the search backend
- MCP protocol standardizes tool access
- Compatible with multiple AI agent frameworks
```

**Our Implementation Status:** ✅ **ALREADY IMPLEMENTED**
- We have `searxng_server.py` as an MCP server
- Integrated with AI Gateway via MCP broker
- 12 domain-specific search tools

---

### **Pattern 2: Local LLM Agent with RAG**

**Project:** [Dev-TechT/local-llm-searxng-agent](https://github.com/Dev-TechT/local-llm-searxng-agent)

**Description:** Python agent connecting local LLM and SearXNG for web search

**Key Features:**
- Combines SearXNG search results with local LLM
- OpenAI-compatible API integration
- Context-aware prompt enhancement
- RAG (Retrieval Augmented Generation) pattern

**Architecture:**
```
User Query → SearXNG Search → Context Gathering → Local LLM → Enhanced Response
```

**Implementation Notes:**
```
- SearXNG provides web search context
- Local LLM (via Ollama/LM Studio) processes results
- Combines original prompt with search context
- Returns synthesized, grounded responses
```

**Our Implementation Status:** 🔄 **PARTIALLY IMPLEMENTED**
- We have SearXNG backend working
- We have LLM backend (LM Studio/vLLM)
- **Missing:** Automatic context injection into LLM prompts
- **Recommendation:** Add RAG pipeline to AI Gateway

---

### **Pattern 3: Integrated AI Stack**

**Project:** [coleam00/local-ai-packaged](https://github.com/coleam00/local-ai-packaged)

**Description:** All-in-one local AI package with SearXNG

**Stack Components:**
- ✅ SearXNG (privacy-respecting search)
- ✅ Ollama (local LLM inference)
- ✅ Supabase (vector database)
- ✅ n8n (workflow automation - 400+ integrations)
- ✅ Web UI for management

**Architecture:**
```
┌─────────────┐
│  n8n (UI)   │
└──────┬──────┘
       │
   ┌───┴──────────────────┐
   │                      │
┌──▼────────┐      ┌─────▼──────┐
│ SearXNG   │      │  Ollama    │
│ (Search)  │◄────►│  (LLM)     │
└───────────┘      └─────┬──────┘
                          │
                   ┌──────▼─────────┐
                   │  Supabase      │
                   │  (Vector DB)   │
                   └────────────────┘
```

**Our Implementation Status:** ✅ **MOSTLY IMPLEMENTED**
- ✅ SearXNG (working, rate limiting disabled)
- ✅ LLM Backend (LM Studio, vLLM, ZAI, Pollinations)
- ✅ Vector Database (Qdrant for RAG)
- ❌ n8n (not integrated)
- ❌ Unified Web UI (missing)

---

### **Pattern 4: Framework Integration**

**Project:** [openclaw/openclaw](https://github.com/openclaw/openclaw) - Feature Request #15068

**Description:** Growing adoption of SearXNG in AI/LLM toolchains

**Status:** Feature request to add SearXNG as web search provider

**Key Insight:**
> "Growing adoption — widely used in AI/LLM toolchains for grounding"

**Integration Pattern:**
```json
{
  "tools": {
    "web": {
      "search": {
        "provider": "searxng",
        "instance_url": "http://localhost:7777"
      }
    }
  }
}
```

**Our Implementation Status:** ✅ **ALREADY IMPLEMENTED**
- We have SearXNG as a web search provider
- Configured for AI Gateway
- Used for grounding LLM responses

---

### **Pattern 5: LangChain/Flowise Integration**

**Project:** [searxng/searxng](https://github.com/searxng/searxng) - Issue #3535

**Description:** Flowise integration request for LangChain

**Key Features:**
- LangChain tool integration
- Flowise drag-and-drop AI workflow builder
- Agent capabilities with web search

**Implementation Notes:**
```
- Requires IP allowlisting for SearXNG instances
- LLM players must self-host instances
- Enables development of AI agents with web search
```

**Our Implementation Status:** 🔄 **POSSIBLE ENHANCEMENT**
- We have the infrastructure
- **Could add:** LangChain tool wrapper
- **Could add:** Flowise-compatible API
- **Recommendation:** Monitor LangChain ecosystem

---

## 📊 **PATTERN ANALYSIS**

### **Common Architectural Patterns**

1. **SearXNG as Search Backend**
   - All implementations use SearXNG for web search
   - Privacy-focused, metasearch capabilities
   - JSON API for programmatic access

2. **Local LLM Integration**
   - Ollama, LM Studio, vLLM for inference
   - OpenAI-compatible APIs
   - RAG for context enhancement

3. **MCP Protocol Adoption**
   - Emerging standard for tool integration
   - Smolagents, OpenClaw adoption
   - Our implementation is ahead of curve

4. **Vector Database for RAG**
   - Supabase, Qdrant for vector storage
   - Semantic search capabilities
   - Cache optimization

5. **Workflow Automation**
   - n8n for low-code integration
   - 400+ service integrations
   - AI agent orchestration

### **Key Success Factors**

✅ **Rate Limiting Disabled** (Critical for AI usage)
✅ **JSON API Access** (Required for LLM integration)
✅ **MCP Protocol** (Standardized tool access)
✅ **Local Deployment** (Privacy, control)
✅ **Multiple Search Engines** (Robustness)

---

## 🎯 **RECOMMENDATIONS FOR OUR IMPLEMENTATION**

### **Priority 1: Add RAG Pipeline** (High Impact)

**What:** Automatic context injection from SearXNG into LLM prompts

**Implementation:**
```python
# In AI Gateway
async def rag_enhanced_prompt(query: str) -> str:
    # 1. Search SearXNG
    results = await searxng.search(query, max_results=5)

    # 2. Format context
    context = "\n".join([r['snippet'] for r in results['results']])

    # 3. Inject into LLM prompt
    enhanced_prompt = f"""
Context from web search:
{context}

User question: {query}

Please answer using the search context above.
"""

    return enhanced_prompt
```

**Benefits:**
- Grounded LLM responses
- Reduced hallucinations
- Up-to-date information

---

### **Priority 2: Add n8n Integration** (Medium Impact)

**What:** Low-code workflow automation with SearXNG + LLM

**Implementation:**
1. Deploy n8n container
2. Configure SearXNG as data source
3. Create AI-powered workflows
4. 400+ service integrations

**Benefits:**
- Visual workflow builder
- Easy integration with external services
- No-code AI agent creation

---

### **Priority 3: Create Unified Web UI** (Medium Impact)

**What:** Single interface for SearXNG + LLM + RAG

**Features:**
- Search interface (SearXNG)
- Chat interface (LLM)
- RAG toggle (grounded vs. creative)
- History management
- API key management

**Implementation:**
- FastAPI backend (existing)
- React/Vue frontend
- WebSocket for real-time responses

---

### **Priority 4: Add LangChain Tool** (Low Priority)

**What:** LangChain-compatible SearXNG tool

**Implementation:**
```python
from langchain.tools import BaseTool

class SearXNGTool(BaseTool):
    name = "searxng_search"
    description = "Search the web using SearXNG"

    def _run(self, query: str) -> str:
        results = searxng.search(query)
        return format_results(results)
```

**Benefits:**
- LangChain ecosystem compatibility
- Flowise drag-and-drop integration
- Wider adoption

---

## 📈 **PERFORMANCE OPTIMIZATIONS**

### **Current Setup**
- ✅ Rate limiting disabled
- ✅ User-Agent headers configured
- ✅ NixOS service (not containers)
- ✅ Single instance (port 7777)

### **Recommended Improvements**

1. **Add Caching Layer**
   - Redis for query caching
   - 5-minute TTL
   - Reduce API calls to upstream engines

2. **Add Load Balancing**
   - Multiple SearXNG instances
   - NGINX/Caddy load balancer
   - High availability

3. **Add Monitoring**
   - Prometheus metrics (already configured)
   - Grafana dashboard
   - Alert on failures

4. **Add Health Checks**
   - `/health` endpoint monitoring
   - Engine availability tracking
   - Automatic failover

---

## 🔧 **TECHNICAL IMPLEMENTATION DETAILS**

### **Rate Limiting Configuration**

**File:** `/etc/nixos/modules/services/searxng.nix`

**Critical Settings:**
```nix
server = {
  limiter = false;  # DISABLE RATE LIMITING
};
limiter = false;  # GLOBAL LIMITER DISABLED
```

**Why Essential:**
- AI agents make many rapid requests
- Rate limiting causes 403 errors
- User-Agent headers alone insufficient
- Must disable at service level

### **MCP Server Configuration**

**File:** `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/mcp_servers/searxng_server.py`

**Tools Provided:**
1. `web_search` - General web search
2. `search_code` - Code repositories (GitHub, GitLab)
3. `search_research` - Academic papers (arXiv, Google Scholar)
4. `search_devops` - DevOps resources (Docker Hub)
5. `search_data` - Data science (Kaggle, Papers with Code)
6. `search_github` - GitHub-specific search
7. `search_nixos_options` - NixOS configuration search
8. `search_mdn` - MDN Web Docs
9. `search_stackoverflow` - Stack Overflow
10. `search_reddit` - Reddit discussions
11. `search_stats` - Search statistics
12. `ping_searxng` - Health check

**Integration:**
```python
# Called via AI Gateway
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H 'Content-Type: application/json' \
  -d '{
    "server": "searxng",
    "tool": "web_search",
    "arguments": {
      "query": "nixos flakes",
      "max_results": 5
    }
  }'
```

---

## 🌟 **UNIQUE FEATURES OF OUR IMPLEMENTATION**

### **Advantages Over Found Patterns**

1. **Domain-Aware Routing** 🎯
   - 12 specialized search tools
   - Quality scoring algorithm
   - Domain detection (code, research, devops, data)

2. **NixOS Integration** 📦
   - Declarative configuration
   - Reproducible deployment
   - System-level service management

3. **Multi-Backend Support** 🔄
   - LM Studio, vLLM, ZAI, Pollinations
   - Graceful fallback chain
   - Context-aware routing

4. **Hybrid RAG** 🧠
   - Vector search (Qdrant)
   - BM25 keyword search
   - Cross-encoder reranking
   - Token-scoped collections

5. **Comprehensive Monitoring** 📊
   - Prometheus metrics
   - Health checks
   - Performance tracking

---

## 📚 **REFERENCES**

### **Projects Studied**
1. [tisDDM/searxng-mcp](https://github.com/tisDDM/searxng-mcp) - MCP server
2. [Dev-TechT/local-llm-searxng-agent](https://github.com/Dev-TechT/local-llm-searxng-agent) - Local LLM agent
3. [coleam00/local-ai-packaged](https://github.com/coleam00/local-ai-packaged) - Integrated stack
4. [openclaw/openclaw](https://github.com/openclaw/openclaw) - Framework integration
5. [searxng/searxng](https://github.com/searxng/searxng) - Flowise integration

### **Documentation**
- [SearXNG Official Docs](https://docs.searxng.org/)
- [SearXNG Instances](https://searx.space/)
- [MCP Protocol Specification](https://modelcontextprotocol.io/)
- [LangChain Documentation](https://python.langchain.com/)

---

## ✅ **CONCLUSION**

Our SearXNG integration is **well-positioned** compared to existing patterns:

- ✅ Following MCP protocol standard
- ✅ Rate limiting disabled for AI usage
- ✅ Domain-aware search routing
- ✅ Integrated with LLM backend
- ✅ RAG capabilities (Qdrant)

**Recommended Next Steps:**
1. Add RAG pipeline for automatic context injection
2. Deploy n8n for workflow automation
3. Create unified web UI
4. Monitor LangChain ecosystem for integration opportunities

**Status:** Production-ready for AI/LLM usage with room for enhancement.
