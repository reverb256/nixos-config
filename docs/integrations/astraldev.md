# AstralDev Integration Guide

**Project**: Multi-Agent Orchestration for Enhanced Clawdbot  
**Source**: /data/@projects/AstralDev/  
**Patterns**: Agent architecture, orchestration, NixOS deployment  

---

## 🎯 Overview

AstralDev provides a sophisticated multi-agent orchestration system that can be adapted for Clawdbot to enable specialized AI agents working together on complex tasks. The system includes 12 specialized agents, a MainOrchestrator for coordination, and comprehensive NixOS deployment patterns.

### Key Components
- **BaseAgent** - Abstract class for all agents
- **AgentPool** - Agent registration and execution management
- **MainOrchestrator** - Pipeline coordination and workflow management
- **AgentContext** - Shared state between agents
- **NixOS Integration** - Systemd services and container deployment

---

## 🏗️ Architecture Patterns

### Agent Base Class

```typescript
// From: /data/@projects/AstralDev/packages/astraldev/src/agents/base-agent.ts
export abstract class BaseAgent {
  protected name: string;
  protected context: AgentContext;
  
  constructor(name: string, context: AgentContext) {
    this.name = name;
    this.context = context;
  }
  
  abstract execute(): Promise<AgentResult>;
  
  protected log(message: string, level: 'info' | 'warn' | 'error'): void {
    console.log(`[${this.name}] ${level.toUpperCase()}: ${message}`);
  }
  
  protected async sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
```

### Agent Context Interface

```typescript
// From: /data/@projects/AstralDev/packages/astraldev/src/agents/base-agent.ts
export interface AgentContext {
  projectId: string;
  requirements: any;
  architecture?: any;
  code?: any;
  securityAnalysis?: any;
  deploymentEnvironment?: any;
  metadata: {
    createdAt: Date;
    lastUpdated: Date;
    version: string;
    startTime: Date;
  };
}
```

### Agent Pool Pattern

```typescript
// From: /data/@projects/AstralDev/packages/astraldev/src/orchestrator/agent-pool.ts
class AgentPool {
  private agents: Map<string, BaseAgent> = new Map();
  
  registerAgent(name: string, agent: BaseAgent): void {
    this.agents.set(name, agent);
    console.log(`Agent registered: ${name}`);
  }
  
  async executeAgent<T>(agentName: string, context: AgentContext): Promise<AgentResult<T>> {
    const agent = this.agents.get(agentName);
    if (!agent) {
      throw new Error(`Agent not found: ${agentName}`);
    }
    
    return await agent.execute();
  }
  
  async executePipeline(agents: string[], context: AgentContext): Promise<AgentResult[]> {
    const results: AgentResult[] = [];
    
    for (const agentName of agents) {
      const result = await this.executeAgent(agentName, context);
      results.push(result);
      
      // Update context with agent result
      if (result.success) {
        context = { ...context, ...result.data };
      }
    }
    
    return results;
  }
}
```

---

## 🚀 Integration with Clawdbot

### Step 1: Adapt BaseAgent Pattern

```typescript
// Clawdbot-specific agent base
abstract class ClawdbotAgent extends BaseAgent {
  protected clawdbot: ClawdbotContext;
  
  constructor(name: string, context: AgentContext, clawdbot: ClawdbotContext) {
    super(name, context);
    this.clawdbot = clawdbot;
  }
  
  protected async sendMessage(channel: string, message: string): Promise<void> {
    await this.clawdbot.sendMessage(channel, message);
  }
  
  protected async queryKnowledgeBase(query: string): Promise<KnowledgeResult[]> {
    return await this.clawdbot.rag.query(query);
  }
}
```

### Step 2: Create Specialized Agents

```typescript
// Code Generation Agent
class CodeGeneratorAgent extends ClawdbotAgent {
  async execute(): Promise<AgentResult> {
    try {
      const requirements = this.context.requirements;
      this.log(`Generating code for requirements: ${requirements}`, 'info');
      
      // Use RAG for context
      const context = await this.queryKnowledgeBase(requirements);
      
      // Generate code using selected model
      const code = await this.clawdbot.model.generate(requirements, context);
      
      // Send to user
      await this.sendMessage('default', `Generated code:\n\`\`\`\`\n${code}\n\`\`\``);
      
      return {
        success: true,
        data: { code, context },
        message: 'Code generated successfully'
      };
    } catch (error) {
      this.log(`Code generation failed: ${error}`, 'error');
      return {
        success: false,
        error: error.message
      };
    }
  }
}

// Code Review Agent
class CodeReviewerAgent extends ClawdbotAgent {
  async execute(): Promise<AgentResult> {
    try {
      const code = this.context.code;
      this.log('Reviewing code for security and performance', 'info');
      
      // Analyze code
      const analysis = await this.analyzeCode(code);
      
      // Send review to user
      await this.sendMessage('default', `Code review:\n${analysis}`);
      
      return {
        success: true,
        data: { analysis, issues: analysis.issues },
        message: 'Code review completed'
      };
    } catch (error) {
      this.log(`Code review failed: ${error}`, 'error');
      return {
        success: false,
        error: error.message
      };
    }
  }
  
  private async analyzeCode(code: string): Promise<CodeAnalysis> {
    // Static analysis
    const staticIssues = await this.staticAnalysis(code);
    
    // Security analysis
    const securityIssues = await this.securityAnalysis(code);
    
    // Performance analysis
    const performanceIssues = await this.performanceAnalysis(code);
    
    return {
      issues: [...staticIssues, ...securityIssues, ...performanceIssues],
      metrics: {
        complexity: this.calculateComplexity(code),
        maintainability: this.calculateMaintainability(code)
      }
    };
  }
}
```

### Step 3: Implement AgentPool for Clawdbot

```typescript
// Clawdbot Agent Pool
class ClawdbotAgentPool extends AgentPool {
  private clawdbot: ClawdbotContext;
  
  constructor(clawdbot: ClawdbotContext) {
    super();
    this.clawdbot = clawdbot;
    this.registerDefaultAgents();
  }
  
  private registerDefaultAgents(): void {
    // Register specialized agents
    this.registerAgent('code-generator', new CodeGeneratorAgent('code-generator', this.createContext(), this.clawdbot));
    this.registerAgent('code-reviewer', new CodeReviewerAgent('code-reviewer', this.createContext(), this.clawdbot));
    this.registerAgent('explainer', new ExplainerAgent('explainer', this.createContext(), this.clawdbot));
    this.registerAgent('search-agent', new SearchAgent('search-agent', this.createContext(), this.clawdbot));
  }
  
  async handleUserMessage(message: string): Promise<void> {
    // Determine which agents to use
    const agentPipeline = this.determineAgentPipeline(message);
    
    // Create context
    const context = this.createContext({
      requirements: message,
      userMessage: message
    });
    
    // Execute pipeline
    const results = await this.executePipeline(agentPipeline, context);
    
    // Send final result
    const finalResult = results[results.length - 1];
    if (finalResult.success) {
      await this.clawdbot.sendMessage('default', finalResult.message);
    } else {
      await this.clawdbot.sendMessage('default', `Error: ${finalResult.error}`);
    }
  }
  
  private determineAgentPipeline(message: string): string[] {
    // Simple keyword-based routing
    if (message.includes('generate') || message.includes('create')) {
      return ['code-generator', 'code-reviewer'];
    } else if (message.includes('review') || message.includes('analyze')) {
      return ['code-reviewer'];
    } else if (message.includes('explain') || message.includes('how does')) {
      return ['explainer'];
    } else if (message.includes('search') || message.includes('find')) {
      return ['search-agent'];
    } else {
      return ['search-agent', 'code-generator'];
    }
  }
  
  private createContext(overrides?: any): AgentContext {
    return {
      projectId: 'clawdbot-default',
      requirements: overrides?.requirements || '',
      metadata: {
        createdAt: new Date(),
        lastUpdated: new Date(),
        version: '2.0',
        startTime: new Date()
      },
      ...overrides
    };
  }
}
```

---

## 🔧 NixOS Integration

### Systemd Service

```nix
# From: /data/@projects/AstralDev/packages/astraldev/nix/modules/services.nix
systemd.services.clawdbot-agents = {
  description = "Clawdbot Multi-Agent System";
  serviceConfig = {
    Type = "simple";
    User = "j_kro";
    Group = "users";
    ExecStart = "${cfg.package}/bin/clawdbot-agents";
    Restart = "always";
    RestartSec = "5";
    MemoryLimit = cfg.maxMemory;
    CPUQuota = cfg.maxCPU;
    Environment = [
      "NODE_ENV=production"
      "CLAWDBOT_STATE_DIR=${cfg.stateDir}"
      "CLAWDBOT_WORKSPACE_DIR=${cfg.workspaceDir}"
    ];
  };
  wantedBy = [ "multi-user.target" ];
};
```

### Flake Configuration

```nix
# From: /data/@projects/AstralDev/packages/astraldev/flake.nix
{
  description = "Enhanced Clawdbot with AstralDev Multi-Agent Patterns";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        
        clawdbot-agents = pkgs.stdenv.mkDerivation {
          name = "clawdbot-agents";
          src = ./src;
          
          buildInputs = with pkgs; [
            nodejs
            typescript
            python3
            qdrant-client
            redis
          ];
          
          buildPhase = ''
            npm install
            npm run build
          '';
          
          installPhase = ''
            mkdir -p $out/bin
            cp dist/index.js $out/bin/clawdbot-agents
            chmod +x $out/bin/clawdbot-agents
          '';
        };
        
        devShell = pkgs.mkShell {
          name = "clawdbot-agents-dev";
          buildInputs = with pkgs; [
            nodejs
            typescript
            python3
            qdrant-client
            redis
            docker-compose
          ];
        };
      in {
        packages = {
          inherit clawdbot-agents;
        };
        devShells.default = devShell;
        nixosConfigurations.clawdbot-agents = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ({ pkgs, ... }: {
              environment.systemPackages = [ clawdbot-agents ];
              systemd.services.clawdbot-agents = {
                description = "Clawdbot Multi-Agent System";
                serviceConfig = {
                  Type = "simple";
                  ExecStart = "${clawdbot-agents}/bin/clawdbot-agents";
                  Restart = "always";
                };
              };
            })
          ];
        };
      });
}
```

---

## 📋 Agent Specifications

### Available Agents

| Agent | Purpose | Model | Temperature |
|--------|---------|--------|-------------|
| RequirementsAnalyzer | Analyze and clarify user requirements | anthropic-claude | 0.3 |
| ArchitectureDesigner | Design system architecture and tech stack | kat-coder-pro-v1 | 0.2 |
| CodeGenerator | Implement code using templates | kat-coder-pro-v1 | 0.3 |
| TestingAgent | Create comprehensive test suites | big-pickle | 0.1 |
| DeploymentOrchestrator | Manage deployment orchestration | glm-4.7 | 0.2 |
| InfrastructureManager | Manage infrastructure and scaling | anthropic-claude | 0.1 |
| ContainerDeploymentAgent | Handle container deployment | kat-coder-pro-v1 | 0.2 |
| MonitoringAgent | Set up monitoring and alerting | glm-4.7 | 0.1 |
| SecurityAnalysisAgent | Perform security analysis | anthropic-claude | 0.1 |
| ComplianceCheckerAgent | Check compliance requirements | glm-4.7 | 0.1 |
| GovernanceAgent | Governance analysis and reporting | anthropic-claude | 0.1 |
| SecurityTestingAgent | Security testing and penetration | anthropic-claude | 0.1 |

### Agent Configuration

```typescript
interface AgentConfig {
  id: string;
  name: string;
  description: string;
  capabilities: AgentCapability[];
  preferredModels: ModelProvider[];
  modelSelectionStrategy: 'adaptive' | 'quality' | 'speed' | 'cost';
  maxTokens: number;
  temperature: number;
  timeout: number;
  retryAttempts: number;
}

enum AgentCapability {
  CODE_GENERATION = 'code_generation',
  CODE_REVIEW = 'code_review',
  ARCHITECTURE_DESIGN = 'architecture_design',
  SECURITY_ANALYSIS = 'security_analysis',
  TESTING = 'testing',
  DEPLOYMENT = 'deployment',
  MONITORING = 'monitoring',
  COMPLIANCE = 'compliance',
  GOVERNANCE = 'governance'
}
```

---

## 🔄 Workflow Patterns

### Pipeline Orchestration

```typescript
// From: /data/@projects/AstralDev/packages/astraldev/src/orchestrator/main-orchestrator.ts
class MainOrchestrator {
  private agentPool: AgentPool;
  
  constructor(agentPool: AgentPool) {
    this.agentPool = agentPool;
  }
  
  async executeFullPipeline(userRequirements: string): Promise<PipelineResult> {
    // Step 1: Requirements Analysis
    const requirementsResult = await this.agentPool.executeAgent('requirements-analyzer', {
      requirements: userRequirements
    });
    
    if (!requirementsResult.success) {
      throw new Error(`Requirements analysis failed: ${requirementsResult.error}`);
    }
    
    // Step 2: Architecture Design
    const architectureResult = await this.agentPool.executeAgent('architecture-designer', {
      requirements: requirementsResult.data.requirements
    });
    
    // Step 3: Code Generation
    const codeResult = await this.agentPool.executeAgent('code-generator', {
      architecture: architectureResult.data.architecture
    });
    
    // Step 4: Testing
    const testResult = await this.agentPool.executeAgent('testing-agent', {
      code: codeResult.data.code
    });
    
    return {
      requirements: requirementsResult.data,
      architecture: architectureResult.data,
      code: codeResult.data,
      tests: testResult.data,
      success: true
    };
  }
  
  async executeSecurityPipeline(code: string): Promise<SecurityResult> {
    const securityAgents = [
      'security-analysis-agent',
      'compliance-checker-agent',
      'governance-agent',
      'security-testing-agent'
    ];
    
    const results = await this.agentPool.executePipeline(securityAgents, {
      code: code
    });
    
    return {
      analysis: results[0].data,
      compliance: results[1].data,
      governance: results[2].data,
      testing: results[3].data,
      success: true
    };
  }
}
```

### Context Sharing

```typescript
// Agent context sharing pattern
class AgentContextManager {
  private contexts: Map<string, AgentContext> = new Map();
  
  createContext(sessionId: string, initialData: any): AgentContext {
    const context: AgentContext = {
      sessionId,
      projectId: 'clawdbot-default',
      requirements: initialData.requirements || '',
      code: initialData.code || '',
      architecture: initialData.architecture || '',
      metadata: {
        createdAt: new Date(),
        lastUpdated: new Date(),
        version: '2.0',
        startTime: new Date()
      }
    };
    
    this.contexts.set(sessionId, context);
    return context;
  }
  
  updateContext(sessionId: string, updates: Partial<AgentContext>): void {
    const context = this.contexts.get(sessionId);
    if (context) {
      Object.assign(context, updates);
      context.metadata.lastUpdated = new Date();
    }
  }
  
  getContext(sessionId: string): AgentContext | null {
    return this.contexts.get(sessionId) || null;
  }
}
```

---

## 🛠️ Implementation Steps

### Step 1: Core Infrastructure

```bash
# Create agent directory structure
mkdir -p ~/code/clawdbot-enhanced/src/agents/{core,specialized}
mkdir -p ~/code/clawdbot-enhanced/src/orchestrator

# Copy base agent patterns
cp /data/@projects/AstralDev/packages/astraldev/src/agents/base-agent.ts \
   ~/code/clawdbot-enhanced/src/agents/core/

# Copy orchestrator patterns
cp /data/@projects/AstralDev/packages/astraldev/src/orchestrator/*.ts \
   ~/code/clawdbot-enhanced/src/orchestrator/
```

### Step 2: Adapt for Clawdbot

```typescript
// File: ~/code/clawdbot-enhanced/src/agents/core/clawdbot-agent.ts
import { BaseAgent, AgentContext, AgentResult } from './base-agent';
import { ClawdbotContext } from '../types';

export abstract class ClawdbotAgent extends BaseAgent {
  protected clawdbot: ClawdbotContext;
  
  constructor(name: string, context: AgentContext, clawdbot: ClawdbotContext) {
    super(name, context);
    this.clawdbot = clawdbot;
  }
  
  protected async sendMessage(channel: string, message: string): Promise<void> {
    await this.clawdbot.sendMessage(channel, message);
  }
  
  protected async queryKnowledgeBase(query: string): Promise<any[]> {
    return await this.clawdbot.rag.query(query);
  }
  
  protected async callModel(prompt: string, options?: any): Promise<string> {
    return await this.clawdbot.model.generate(prompt, options);
  }
}
```

### Step 3: Create Specialized Agents

```typescript
// File: ~/code/clawdbot-enhanced/src/agents/specialized/code-generator.ts
import { ClawdbotAgent } from '../core/clawdbot-agent';
import { AgentResult } from '../core/base-agent';

export class CodeGeneratorAgent extends ClawdbotAgent {
  async execute(): Promise<AgentResult> {
    try {
      const requirements = this.context.requirements;
      this.log(`Generating code for: ${requirements}`, 'info');
      
      // Get relevant context from knowledge base
      const context = await this.queryKnowledgeBase(requirements);
      
      // Generate code using selected model
      const prompt = this.buildPrompt(requirements, context);
      const code = await this.callModel(prompt, { 
        model: 'kat-coder-pro-v1',
        temperature: 0.3 
      });
      
      // Send result to user
      await this.sendMessage('default', `Generated code:\n\`\`\`\`\n${code}\n\`\`\``);
      
      return {
        success: true,
        data: { code, context },
        message: 'Code generated successfully'
      };
    } catch (error) {
      this.log(`Code generation failed: ${error}`, 'error');
      return {
        success: false,
        error: error.message
      };
    }
  }
  
  private buildPrompt(requirements: string, context: any[]): string {
    const contextStr = context.map(c => `- ${c.title}: ${c.snippet}`).join('\n');
    
    return `Generate code based on the following requirements:
    
Requirements:
${requirements}

Relevant context:
${contextStr}

Please provide clean, well-documented code that meets the requirements.`;
  }
}
```

### Step 4: NixOS Configuration

```nix
# File: ~/code/clawdbot-enhanced/modules/clawdbot-agents.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.clawdbot-agents;
in {
  options.services.clawdbot-agents = {
    enable = mkEnableOption "Enable Clawdbot multi-agent system";
    
    package = mkOption {
      type = types.package;
      default = pkgs.clawdbot-agents;
      description = "Clawdbot agents package";
    };
    
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/clawdbot-agents";
      description = "State directory for Clawdbot agents";
    };
    
    workspaceDir = mkOption {
      type = types.str;
      default = "/home/j_kro/.clawd";
      description = "Workspace directory for Clawdbot";
    };
    
    maxMemory = mkOption {
      type = types.str;
      default = "4G";
      description = "Maximum memory for agents";
    };
    
    maxCPU = mkOption {
      type = types.str;
      default = "200%";
      description = "Maximum CPU quota";
    };
    
    agents = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "Enable this agent";
          model = mkOption {
            type = types.str;
            default = "kat-coder-pro-v1";
            description = "AI model to use";
          };
          temperature = mkOption {
            type = types.float;
            default = 0.3;
            description = "Model temperature";
          };
          timeout = mkOption {
            type = types.int;
            default = 30;
            description = "Agent timeout in seconds";
          };
        };
      });
      default = {};
      description = "Agent configurations";
    };
  };
  
  config = mkIf cfg.enable {
    systemd.services.clawdbot-agents = {
      description = "Clawdbot Multi-Agent System";
      serviceConfig = {
        Type = "simple";
        User = "j_kro";
        Group = "users";
        ExecStart = "${cfg.package}/bin/clawdbot-agents";
        Restart = "always";
        RestartSec = "5";
        MemoryLimit = cfg.maxMemory;
        CPUQuota = cfg.maxCPU;
        Environment = [
          "NODE_ENV=production"
          "CLAWDBOT_STATE_DIR=${cfg.stateDir}"
          "CLAWDBOT_WORKSPACE_DIR=${cfg.workspaceDir}"
        ];
      };
      wantedBy = [ "multi-user.target" ];
    };
    
    # Ensure state directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 j_kro users -"
    ];
  };
}
```

---

## 📊 Monitoring & Logging

### Agent Performance Monitoring

```typescript
class AgentMonitor {
  private metrics: Map<string, AgentMetrics> = new Map();
  
  recordAgentExecution(agentName: string, duration: number, success: boolean): void {
    const current = this.metrics.get(agentName) || {
      executions: 0,
      totalDuration: 0,
      successes: 0,
      failures: 0
    };
    
    current.executions++;
    current.totalDuration += duration;
    if (success) {
      current.successes++;
    } else {
      current.failures++;
    }
    
    this.metrics.set(agentName, current);
  }
  
  getMetrics(agentName: string): AgentMetrics | null {
    return this.metrics.get(agentName) || null;
  }
  
  getAllMetrics(): Map<string, AgentMetrics> {
    return new Map(this.metrics);
  }
}

interface AgentMetrics {
  executions: number;
  totalDuration: number;
  successes: number;
  failures: number;
  averageDuration: number;
  successRate: number;
}
```

### Health Check Endpoint

```typescript
class AgentHealthCheck {
  constructor(private agentPool: AgentPool) {}
  
  async healthCheck(): Promise<HealthStatus> {
    const checks = await Promise.all([
      this.checkAgentHealth(),
      this.checkModelConnectivity(),
      this.checkKnowledgeBase(),
      this.checkResourceUsage()
    ]);
    
    return {
      healthy: checks.every(check => check.healthy),
      checks,
      timestamp: new Date()
    };
  }
  
  private async checkAgentHealth(): Promise<HealthCheck> {
    try {
      const result = await this.agentPool.executeAgent('health-check', {
        test: true
      });
      return {
        name: 'agents',
        healthy: result.success,
        message: result.success ? 'All agents healthy' : result.error
      };
    } catch (error) {
      return {
        name: 'agents',
        healthy: false,
        message: error.message
      };
    }
  }
}
```

---

## 🧪 Testing

### Unit Tests

```typescript
// File: ~/code/clawdbot-enhanced/tests/agents/code-generator.test.ts
import { CodeGeneratorAgent } from '../../../src/agents/specialized/code-generator';
import { AgentContext } from '../../../src/agents/core/base-agent';

describe('CodeGeneratorAgent', () => {
  let agent: CodeGeneratorAgent;
  let mockContext: AgentContext;
  let mockClawdbot: any;
  
  beforeEach(() => {
    mockClawdbot = {
      sendMessage: jest.fn(),
      queryKnowledgeBase: jest.fn(),
      model: {
        generate: jest.fn()
      }
    };
    
    mockContext = {
      projectId: 'test',
      requirements: 'Create a simple REST API',
      metadata: {
        createdAt: new Date(),
        lastUpdated: new Date(),
        version: '2.0',
        startTime: new Date()
      }
    };
    
    agent = new CodeGeneratorAgent('test-agent', mockContext, mockClawdbot);
  });
  
  it('should generate code successfully', async () => {
    // Mock knowledge base response
    mockClawdbot.queryKnowledgeBase.mockResolvedValue([
      { title: 'Express.js example', snippet: 'app.get("/api", handler)' }
    ]);
    
    // Mock model response
    mockClawdbot.model.generate.mockResolvedValue('app.get("/api", (req, res) => { res.json({}); });');
    
    const result = await agent.execute();
    
    expect(result.success).toBe(true);
    expect(result.data.code).toContain('app.get');
    expect(mockClawdbot.sendMessage).toHaveBeenCalledWith(
      'default',
      expect.stringContaining('Generated code:')
    );
  });
  
  it('should handle errors gracefully', async () => {
    // Mock model to throw error
    mockClawdbot.model.generate.mockRejectedValue(new Error('Model unavailable'));
    
    const result = await agent.execute();
    
    expect(result.success).toBe(false);
    expect(result.error).toBe('Model unavailable');
  });
});
```

### Integration Tests

```typescript
// File: ~/code/clawdbot-enhanced/tests/integration/agent-pool.test.ts
import { ClawdbotAgentPool } from '../../src/orchestrator/clawdbot-agent-pool';

describe('ClawdbotAgentPool Integration', () => {
  let agentPool: ClawdbotAgentPool;
  let mockClawdbot: any;
  
  beforeEach(async () => {
    mockClawdbot = {
      sendMessage: jest.fn(),
      rag: { query: jest.fn() },
      model: { generate: jest.fn() }
    };
    
    agentPool = new ClawdbotAgentPool(mockClawdbot);
    await agentPool.initialize();
  });
  
  it('should execute code generation pipeline', async () => {
    const message = 'Generate a Python function to fetch JSON from URL';
    
    await agentPool.handleUserMessage(message);
    
    expect(mockClawdbot.sendMessage).toHaveBeenCalledWith(
      'default',
      expect.stringContaining('Generated code:')
    );
  });
  
  it('should route to appropriate agents based on keywords', async () => {
    const codeReviewMessage = 'Review this code: function test() { return true; }';
    const searchMessage = 'Find examples of error handling in TypeScript';
    
    await agentPool.handleUserMessage(codeReviewMessage);
    expect(mockClawdbot.rag.query).not.toHaveBeenCalled();
    
    await agentPool.handleUserMessage(searchMessage);
    expect(mockClawdbot.rag.query).toHaveBeenCalled();
  });
});
```

---

## 📚 Best Practices

### Agent Design
1. **Single Responsibility**: Each agent should have one clear purpose
2. **Context Awareness**: Agents should be aware of shared context
3. **Error Handling**: All agents should handle errors gracefully
4. **Logging**: Comprehensive logging for debugging and monitoring
5. **Timeouts**: All operations should have reasonable timeouts

### Performance
1. **Async Operations**: Use async/await for all I/O operations
2. **Connection Pooling**: Reuse connections to external services
3. **Caching**: Cache frequently accessed data
4. **Resource Limits**: Set appropriate memory and CPU limits
5. **Monitoring**: Monitor agent performance and resource usage

### Security
1. **Input Validation**: Validate all user inputs
2. **Sanitization**: Sanitize code before execution
3. **Authentication**: Secure access to external services
4. **Audit Logging**: Log all agent actions
5. **Error Information**: Don't expose sensitive information in errors

---

## 🔗 References

### Key Files
- **BaseAgent**: `/data/@projects/AstralDev/packages/astraldev/src/agents/base-agent.ts`
- **AgentPool**: `/data/@projects/AstralDev/packages/astraldev/src/orchestrator/agent-pool.ts`
- **MainOrchestrator**: `/data/@projects/AstralDev/packages/astraldev/src/orchestrator/main-orchestrator.ts`
- **NixOS Service**: `/data/@projects/AstralDev/packages/astraldev/nix/modules/services.nix`
- **Flake Configuration**: `/data/@projects/AstralDev/packages/astraldev/flake.nix`

### Documentation
- **AstralDev README**: `/data/@projects/AstralDev/README.md`
- **Architecture Documentation**: `/data/@projects/AstralDev/docs/`
- **Nix Integration Guide**: `/data/@projects/AstralDev/NIX_INTEGRATION_COMPLETE.md`

### External Resources
- **NixOS Documentation**: https://nixos.org/manual/nixos/stable/
- **TypeScript Documentation**: https://www.typescriptlang.org/docs/
- **Node.js Documentation**: https://nodejs.org/docs/

---

**Last Updated**: 2026-01-17  
**Version**: 1.0  
**Status**: Ready for Implementation