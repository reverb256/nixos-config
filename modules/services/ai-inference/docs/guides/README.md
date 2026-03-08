# AI Gateway Guides

**Quick reference guides** and **how-to documentation** for the AI Inference Gateway.

## What You'll Find Here

These guides provide **practical, actionable information** for daily operations and development. Each guide focuses on a specific topic with concrete examples and troubleshooting steps.

**For architectural details**, see [Implementation Documentation](../implementation/).
**For historical context**, see [Archive](../archive/).

---

## Available Guides

### [Middleware Quick Reference](middleware-quick-reference.md)
**Purpose:** Fast lookup for middleware architecture and configuration

**What's Inside:**
- Middleware execution order diagram
- Component file locations
- Environment variable reference
- Configuration examples
- Troubleshooting commands

**Best For:** Developers who need quick answers about middleware setup

**Prerequisites:** Basic understanding of Python and NixOS configuration

---

### [Semantic Cache Guide](semantic-cache.md)
**Purpose:** Understanding and configuring semantic caching

**What's Inside:**
- How semantic caching works (vector similarity matching)
- Redis + Qdrant architecture
- Configuration options
- Performance tuning guidelines

**Best For:** Operators optimizing cache performance

**Why It Matters:** Semantic caching can reduce API costs by 40-60% by serving similar requests from cache instead of calling the backend.

**Prerequisites:** Familiarity with Redis and vector databases

---

### [Tool Calling Guide](tool-calling.md)
**Purpose:** Implementing and using tool calling features

**What's Inside:**
- Tool calling architecture
- Implementation patterns
- Configuration examples
- Troubleshooting

**Best For:** Developers integrating MCP (Model Context Protocol) tools

**Why It Matters:** Tool calling enables AI models to interact with external APIs (web search, databases, etc.) for agentic workflows.
