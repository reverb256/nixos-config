# AI Inference Gateway - System Prompts Configuration

## Overview

The AI inference gateway now supports configurable system prompts for different request types, enabling automatic prompt selection based on request analysis.

## Configuration

### NixOS Module

Enable and configure system prompts in your NixOS configuration:

```nix
services.ai-inference = {
  enable = true;
  
  systemPrompts = {
    enable = true;
    
    # Default prompt for all requests
    default = "You are a helpful AI assistant.";
    
    # Request-type specific prompts
    coding = "You are an expert coding assistant. Write clean, efficient, and well-documented code.";
    reasoning = "You are an expert reasoning assistant. Think step-by-step and provide clear explanations.";
    analysis = "You are an expert analysis assistant. Provide thorough and structured analysis.";
    agentic = "You are an autonomous agent capable of multi-step planning and execution.";
    fast = "You are a fast and efficient assistant. Provide concise, direct answers.";
    
    # Custom prompts by name
    custom = {
      nixos = "You are a NixOS configuration expert. Always use lib.mkOptionDefault for shared modules.";
      kubernetes = "You are a Kubernetes expert. Use best practices for manifests and configurations.";
    };
  };
};
```

## API Endpoints

### GET /system-prompts

Retrieve current system prompts configuration.

**Response:**
```json
{
  "enabled": true,
  "default": "You are a helpful AI assistant.",
  "coding": "You are an expert coding assistant...",
  "reasoning": "You are an expert reasoning assistant...",
  "analysis": "You are an expert analysis assistant...",
  "agentic": "You are an autonomous agent...",
  "fast": "You are a fast and efficient assistant...",
  "custom": {
    "nixos": "You are a NixOS configuration expert...",
    "kubernetes": "You are a Kubernetes expert..."
  }
}
```

### POST /system-prompts

Update system prompts configuration.

**Request:**
```json
{
  "enabled": true,
  "default": "New default prompt",
  "coding": "New coding prompt",
  "custom": {
    "nixos": "Updated NixOS prompt"
  }
}
```

**Response:**
```json
{
  "status": "updated"
}
```

## Automatic Prompt Selection

The gateway automatically selects system prompts based on request analysis:

| Pattern Detected | Prompt Used |
|-----------------|-------------|
| `def `, `class `, `function`, `import ` | `coding` |
| `agent`, `workflow`, `multi-step`, `plan` | `agentic` |
| `reason`, `think`, `step`, `explain` | `reasoning` |
| `quickly`, `asap`, `fast`, `brief` | `fast` |
| No patterns detected | `default` |

## Environment Variables

The gateway reads system prompts from these environment variables:

| Variable | Description |
|----------|-------------|
| `SYSTEM_PROMPTS_ENABLED` | Enable/disable system prompts (true/false) |
| `SYSTEM_PROMPTS_DEFAULT` | Default system prompt |
| `SYSTEM_PROMPTS_CODING` | Coding-specific prompt |
| `SYSTEM_PROMPTS_REASONING` | Reasoning-specific prompt |
| `SYSTEM_PROMPTS_ANALYSIS` | Analysis-specific prompt |
| `SYSTEM_PROMPTS_AGENTIC` | Agentic-specific prompt |
| `SYSTEM_PROMPTS_FAST` | Fast response prompt |
| `SYSTEM_PROMPTS_CUSTOM` | JSON-encoded custom prompts |

## Examples

### Example 1: Configure for NixOS Development

```nix
services.ai-inference.systemPrompts = {
  enable = true;
  default = "You are a helpful AI assistant.";
  coding = "You are a NixOS expert. Always use lib.mkOptionDefault for shared modules.";
  custom.nixos = "You are a NixOS configuration expert.";
};
```

### Example 2: Disable System Prompts

```nix
services.ai-inference.systemPrompts.enable = false;
```

### Example 3: Query Current Configuration

```bash
curl http://127.0.0.1:8080/system-prompts
```

### Example 4: Update Configuration

```bash
curl -X POST http://127.0.0.1:8080/system-prompts \
  -H "Content-Type: application/json" \
  -d '{
    "enabled": true,
    "coding": "You are a coding expert. Write clean, maintainable code.",
    "custom": {
      "nixos": "You are a NixOS expert. Use lib.mkOptionDefault."
    }
  }'
```

## Integration with Request Processing

When a request is processed:

1. **Check if system prompt is already provided** in the request
2. **If not provided and systemPrompts.enabled=true**:
   - Analyze request content for patterns
   - Select appropriate prompt based on detected patterns
   - Add system prompt to message list
3. **Route request to backend** with system prompt included

## Benefits

1. **Consistent Behavior**: All requests get appropriate context
2. **Automatic Selection**: No manual prompt management needed
3. **Customizable**: Easy to add domain-specific prompts
4. **Dynamic Updates**: Can change prompts without restart
5. **Pattern Detection**: Intelligent prompt selection based on content

## Notes

- System prompts are added as the first message with `role: "system"`
- User-provided system prompts in requests take precedence
- Pattern detection is keyword-based and can be extended
- Custom prompts are stored as name → prompt mappings

---

**Version**: 1.0 | **Updated**: 2026-03-15
**Location**: `/etc/nixos/docs/AI_INFERENCE_SYSTEM_PROMPTS.md`
